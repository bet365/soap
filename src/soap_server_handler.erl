%%
%% %CopyrightBegin%
%%
%% Copyright Hillside Technology Ltd. 2016. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% %CopyrightEnd%
%%

%%% This is the generic part of the SOAP server implementation. The http server
%%% calls "handle_message" for each request.
%%% 
%%% Takes care of the SOAP specific stuff such as decoding and encoding the
%%% xml, some error handling on the level of the soap protocol, etc.
%%%
%%% Invokes the call-back functions in the handler module that implements the 
%%% functionality of the SOAP service.

-module(soap_server_handler).

-include("soap.hrl").

%%% functions called by the HTTP server
-export([new_req/4]).
-export([handle_message/2]).
-export([check_http_conformance/1]).

%%% internal export
-export([xml_parser_cb_wrapped/2]).

-type server_http_response() :: soap:server_http_response().
-type soap_req() :: soap_req:soap_req().
-type soap_handler_response() :: soap:soap_handler_response(any()).
-type protocol_error() :: soap:protocol_error().
-type soap_error_code() :: server | client | atom().

%%% state that is maintained by the xml parser
-record(p_state, {
    soap_version :: undefined | '1.1' | '1.2',
    soap_namespace :: undefined | string(),
    handler :: undefined | module(),
    header_parser :: undefined | fun(),
    body_parser :: undefined | fun(),
    header_handler :: undefined | fun(),
    body_handler :: undefined | fun(),
    state :: atom(),
    %% soap_req is passed to the handler module, and may be modified by it.
    soap_req :: soap_req(),
    %% another parser can be used to parse the header and body,
    %% this has it's own state. 
    p2_state :: any(),
    %% The handler module also has it's own state
    %% Note that this state exists only for the duration of the request.
    handler_state :: any()
}).

%% used to collect some information in case of an error
-record(soap_error, {
    type :: soap_error_code(),
    stacktrace :: any(), 
    description :: string(),
    soap_req :: soap_req(),
    class :: atom(),
    handler :: module(),
    handler_state :: any(),
    reason :: any()}).

-type soap_error() :: #soap_error{}.

%%% ============================================================================
%%% Exported functions
%%% ============================================================================

%% creates the 'soap_req' that will be used during the handling of the request 
%% (or triggers a resoponse immediately, in case of an error).
-spec new_req(Handler :: module(), Server :: atom(), 
                            Options :: any(), Server_req :: any())
    -> server_http_response() | {continue, soap_req()}.
new_req(Handler, Server, Options, Server_req) ->
    {module, _} = code:ensure_loaded(Handler),
    New_req = soap_req:new(Server, Server_req, Handler),
    try 
        {Soap_req, Handler_state} = Handler:init(New_req, Options),
        {continue, soap_req:set_handler_state(Soap_req, Handler_state)}
    catch
        %% TODO: what if the `undef` is caused by an error in the `init` 
        %% function, rather than by the `init` function not being defined?
        error:undef ->
            {continue, soap_req:set_handler_state(New_req, Options)};
        Class:Reason:Stacktrace ->
            Soap_error = #soap_error{type = server,
                                     class = Class,
                                     stacktrace = Stacktrace,
                                     reason = Reason,
                                     handler = Handler,
                                     soap_req = New_req,
                                     description = "Error in initialization"},
            Exception_resp = make_exception(Handler, Soap_error),
            Error_s_req = soap_req:set_resp(Exception_resp, New_req),
            soap_req:http_response(Error_s_req)
    end.

%% parses the message, invokes the callbacks implemented by the handler 
%% module, and creates a response message.
-spec handle_message(Message :: binary(), Soap_req :: soap_req()) -> 
    server_http_response().
handle_message(Message, Soap_req) ->
    Handler = soap_req:handler(Soap_req),
    Handler_state = soap_req:handler_state(Soap_req),
    %% Call the erlsom sax parser with a callback that
    %% takes off and inspects the envelope.
    %% The callback uses the    decoder that is defined in the 
    %% handler module to parse header(s) and body.
    Header_handler = get_function(Handler, header, 3, fun skip/3),
    Body_handler = get_function(Handler, body, 3, fun handle/3),
    try 
        erlsom_sax:parseDocument(Message, 
                                 #p_state{handler = Handler,
                                 handler_state = Handler_state,
                                 header_handler = Header_handler,
                                 body_handler = Body_handler,
                                 soap_req = Soap_req,
                                 state = start},
                                 fun xml_parser_cb_wrapped/2, []) of
        {ok, SoapReq2, _Tail} ->
            soap_req:http_response(SoapReq2)
    catch
        Class:Reason:Stacktrace ->
            Soap_error = 
                case {Class, Reason} of
                    {throw, #soap_error{}} ->
                        Reason;
                    {_, _} ->
                        #soap_error{type = client,
                                    class = Class,
                                    stacktrace = Stacktrace,
                                    reason = Reason,
                                    handler = Handler,
                                    handler_state = Handler_state,
                                    soap_req = Soap_req,
                                    description = "Error parsing XML"}
                end, 
            Exception_resp = make_exception(Handler, Soap_error),
            Error_soap_req = Soap_error#soap_error.soap_req,
            Error_s_req2 = soap_req:set_resp(Exception_resp, Error_soap_req),
            soap_req:http_response(Error_s_req2)
    end.

%% This function can be called by the server integration middleware.
%% It must be called when method and headers are known, but it is not yet 
%% clear which soap version is used (because that has to come from the body). 
-spec check_http_conformance(soap_req()) 
    -> server_http_response() | {continue, soap_req()}.
check_http_conformance(Soap_req) ->
    Handler = soap_req:handler(Soap_req),
    Handler_state = soap_req:handler_state(Soap_req),
    try Handler:check_http_conformance(Soap_req, Handler_state) of
        {continue, Soap_req2, Handler_st2} ->
            Soap_req3 = soap_req:set_handler_state(Soap_req2, Handler_st2),
            {continue, Soap_req3};
        {_, _, Soap_req2, _} = Handler_res ->
            Soap_req3 = soap_req:set_resp(Handler_res, Soap_req2),
            soap_req:http_response(Soap_req3)
    catch
        _:_ ->
            {continue, Soap_req}
    end.

%%% ============================================================================
%%% Internal functions
%%% ============================================================================

%% called if there is something wrong with the request, from a protocol 
%% compliance point of view. 
%% Will call the 'protocol_error' callback in the handler module, if it 
%% exists. Otherwise it will respond with a default fault message.
-spec protocol_error(protocol_error(), soap_req()) -> 
    {stop, soap_req()} | {continue, soap_req()}.
protocol_error(Error_type, Soap_req) ->
    Handler = soap_req:handler(Soap_req),
    Handler_state = soap_req:handler_state(Soap_req),
    try Handler:protocol_error(Error_type, Soap_req, Handler_state) of
        {continue, Soap_req2, Handler_st2} ->
            Soap_req3 = soap_req:set_handler_state(Soap_req2, Handler_st2),
            {continue, Soap_req3};
        {_, _, Soap_req2, _} = Handler_res ->
            Soap_req3 = soap_req:set_resp(Handler_res, Soap_req2),
            {stop, Soap_req3}
    catch
        _:_ ->
            default_protocol_error_handler(Error_type, Soap_req, Handler_state)
    end.

%% this function is called when method and headers are known, and also 
%% the soap version is known.
-spec check_soap_conformance(soap_req()) -> 
    {stop, soap_req()} | {continue, soap_req()}.
check_soap_conformance(Soap_req) ->
    Handler = soap_req:handler(Soap_req),
    Handler_state = soap_req:handler_state(Soap_req),
    try Handler:check_soap_conformance(Soap_req, Handler_state) of
        {continue, Soap_req2, Handler_st2} ->
            Soap_req3 = soap_req:set_handler_state(Soap_req2, Handler_st2),
            {continue, Soap_req3};
        {_, _, Soap_req2, _} = Soap_resp ->
            Soap_req3 = soap_req:set_resp(Soap_resp, Soap_req2),
            {stop, Soap_req3}
    catch
        error:Reason when Reason == function_clause; Reason == undef ->
            default_conformance_check(Soap_req);
        Class:Reason:Stacktrace ->
            throw(callback_error(Class, Reason, Soap_req, Handler_state, Stacktrace))
    end.


%% Basic profile 1.0: 
%% R1114 An INSTANCE SHOULD use a "405 Method not Allowed" HTTP status code
%% if the request method was not "POST".

%% SOAP 1.1 spec: 
%% HTTP applications MUST use the media type "text/xml" according to RFC
%% 2376 [3] when including SOAP entity bodies in HTTP messages.
%%
%% Basic profile 1.1:
%% R1115 An INSTANCE SHOULD use a "415 Unsupported Media Type" HTTP status
%% code if the Content-Type HTTP request header did not have a value 
%% consistent with the value specified for the corresponding binding of the
%% input message.
%%
%% SOAP 1.2 spec:
%% In the SOAP 1.2 HTTP binding, the Content-type header should be "application/soap+xml"
%% TODO: there is a problem if the first check fails, but `protocol_error` callback 
%% overrules it - in that case the second check is never performed.
%%
%% But: for soap with attachments (W3C Note "SOAP Messages with Attachments") the 
%% Content-Type must be "Multipart/Related", so we also allow that by default.
%%
-spec default_conformance_check(soap_req()) ->
    {stop, soap_req()} | {continue, soap_req()}.
default_conformance_check(Soap_req) ->
    case check_conformance(soap_req:soap_version(Soap_req), 
                           soap_req:content_type(Soap_req), 
                           soap_req:method(Soap_req)) of
        true ->
            {continue, Soap_req};
        Error ->
            protocol_error(Error, Soap_req)
    end.

check_conformance(undefined, _, _) ->
    true;
check_conformance(Version, Content_type, Method) ->
    case check_method(Version, Method) of
        true ->
            check_content_type(Version, Content_type);
        Error ->
            Error
    end.

check_content_type(_, undefined) ->
    true;
check_content_type(Version, Content_type) ->
    check_content_type2(Version, string:to_lower(Content_type)).

check_content_type2('1.1', "text/xml" ++ _) ->
    true;
check_content_type2('1.2', "application/soap+xml" ++ _) ->
    true;
check_content_type2(_, "multipart/related" ++ _) ->
    true;
check_content_type2(_, Media_type) ->
    {unsupported_media_type, Media_type}.

check_method(_, undefined) ->
    true;
check_method(_, "POST") ->
    true;
check_method('1.2', "GET") ->
    true;
check_method(_, Method) ->
    {method_not_allowed, Method}.


default_protocol_error_handler(Error, Soap_req, Handler_state) ->
    Code = map_error(Error),
    {stop, soap_req:set_resp({error, Code, Soap_req, Handler_state}, Soap_req)}.

map_error({method_not_allowed, _}) -> 
    405;
map_error({unsupported_media_type, _}) -> 
    415.

%% returns {ok, SoapReq, Tail} | {error, ErrorCode, SoapReq} where
%%   SoapReq = 
%%   Tail = The rest of the Body (after the XML message)
xml_parser_cb_wrapped(Event, #p_state{state = _Parser_state,
                                      handler = Handler,
                                      handler_state = Handler_state,
                                      soap_req = Soap_req} = S) ->
    try
        R = xml_parser_cb(Event, S),
        %% io:format("R: ~P~n", [R, 8]),
        R
    catch
        %% TODO: differentiate more (perhaps improve erlsom error codes)
        throw:#soap_error{} = Soap_error ->
            throw(Soap_error#soap_error{soap_req = Soap_req, handler_state = Handler_state});
        Class:Reason:Stacktrace ->
            throw(#soap_error{type = client,
                              class = Class,
                              stacktrace = Stacktrace,
                              reason = Reason,
                              handler = Handler,
                              handler_state = Handler_state,
                              soap_req = Soap_req,
                              description = "Error parsing XML"})
    end.

%% Parses the message and calls the callback functions in the handler module.
%%
%% This is an erlsom - sax callback function. It is called for every SAX 
%% event. It keeps track of the progress of the parsing in the #p_state{}
%% record.
%%
%% The SOAP envelope is parsed by this function. For the contents (header
%% blocks and body), the sax events are handed over to another sax callback
%% function. Which one that is, is specified by the handler module for the 
%% service.

%% Getting started
xml_parser_cb(startDocument, #p_state{state = start} = S) ->
    S#p_state{state = started};
xml_parser_cb(startDocument, #p_state{state = started} = S) ->
    S#p_state{state = started};

%% Read the <Envelope> tag
xml_parser_cb({startElement, Namespace, "Envelope", _Prfx, _Attrs},
              #p_state{state = started, soap_req = Soap_req} = S) 
    when Namespace == ?SOAP_NS; Namespace == ?SOAP12_NS ->
    %% determine the SOAP version from the namespace
    Version = 
        case Namespace of
            ?SOAP_NS -> '1.1';
            ?SOAP12_NS -> '1.2'
        end,
    Soap_req2 = soap_req:set_soap_version(Soap_req, Version),
    case check_soap_conformance(Soap_req2) of
        {continue, Soap_req3} ->
            S#p_state{state = envelope, 
                      soap_namespace = Namespace,
                      soap_version = Version,
                      soap_req = Soap_req3};
        {stop, Soap_req4} ->
            S#p_state{state = done, 
                      soap_namespace = Namespace,
                      soap_version = Version,
                      soap_req = Soap_req4}
    end;

%% Read the <Header> tag (if it exists), and then parse the header blocks
xml_parser_cb({startElement, NS, "Header", _Prfx, _Attrs},
              #p_state{state = envelope,
              soap_namespace = NS} = S) ->
    S#p_state{state = header};

%% empty header
xml_parser_cb({endElement, NS, "Header", _Prfx},
              #p_state{state = header,
                       soap_namespace = NS} = S) ->
    S#p_state{state = envelope};

%% Start element of a header block
xml_parser_cb({startElement, Namespace, _LocalName, _Prfx, _Attrs} = Event,
              #p_state{state = header, soap_req = Soap_req,
                       handler = Handler,
                       handler_state = Handler_s} = S) ->
    {ok, {Header_parser, Start_state}, Soap_req2, Handler_s2} = 
        get_header_parser(Handler, Namespace, Soap_req, Handler_s),
    %% insert a 'startDocument' event to get the header parser going
    S1 = parse_event(Header_parser, startDocument, Start_state, "Header"),
    %% and pass it the original event
    S2 = parse_event(Header_parser, Event, S1, "Header"),
    S#p_state{state = parsing_header, p2_state = S2, soap_req = Soap_req2, 
              header_parser = Header_parser,
              handler_state = Handler_s2};

%% end of the header
xml_parser_cb({endElement, NS, "Header", _Prfx},
              #p_state{state = parsing_header, 
              soap_namespace = NS} = S) ->
    S#p_state{state = envelope}; 

%% all events that are part of the header are passed to the header parser.
xml_parser_cb(Event, #p_state{state = parsing_header, 
                              header_parser = H_parser,
                              header_handler = H_handler,
                              soap_req = Req,
                              handler_state = Handler_s,
                              p2_state = P2_s} = S) ->
    case H_parser(Event, P2_s) of
        %% reached the end of this header
        {result, Parsed_header} ->
            %% Call the handler for the header.
            {ok, Req2, Handler_s2} = 
                try_header_fun(
                    fun () -> 
                        H_handler(Parsed_header, Req, Handler_s) 
                    end,
                    Req, Handler_s),
            S#p_state{state = header, p2_state = undefined, 
                      soap_req = Req2, handler_state = Handler_s2};
        P2_s2 ->
            S#p_state{p2_state = P2_s2}
    end;

%% read the <body> tag
xml_parser_cb({startElement, NS, "Body", _Prfx, _Attrs},
              #p_state{state = envelope,
                       soap_namespace = NS} = S) ->
    S#p_state{state = body};

%% first element of the body
xml_parser_cb({startElement, Namespace, _LocalName, _Prfx, _Attrs} = Event,
              #p_state{state = body, 
                       soap_req = Soap_req,
                       handler = Handler,
                       handler_state = Handler_s} = S) ->
    B_parser_selector = 
        get_function(Handler, body_parser, 3, fun default_parser/3),
    {ok, {Body_parser, Start_state}, Soap_req2, Handler_s2} = 
        B_parser_selector(Namespace, Soap_req, Handler_s),
    %% insert a 'startDocument' event to get the body parser going
    S1 = Body_parser(startDocument, Start_state),
    %% and pass it the original event.
    S2 = Body_parser(Event, S1),
    S#p_state{state = parsing_body, p2_state = S2, soap_req = Soap_req2, 
              body_parser = Body_parser,
              handler_state = Handler_s2};

%% empty body
xml_parser_cb({endElement, NS, "Body", _Prfx},
              #p_state{state = body,
                       soap_namespace = NS} = S) ->
    S#p_state{state = body_done};

%% end of the (not-empty) body
xml_parser_cb({endElement, NS, "Body", _Prfx},
              #p_state{state = parsing_body, 
                               soap_namespace = NS,
                               body_handler = Body_handler,
                               body_parser = B_parser,
                               p2_state = P2_s,
                               soap_req = Soap_req,
                               handler_state = Handler_s} = S) ->
    Parsed_body = B_parser(endDocument, P2_s),
    {Handler_s2, Soap_req2} = 
        try
            %% call the handler module and get the response
            Handler_resp = Body_handler(Parsed_body, Soap_req, Handler_s),
            %% and encode it.
            encode_soap_resp(Handler_resp)
        catch
            Class:Reason:Stacktrace -> 
                throw(#soap_error{class = Class, 
                                  reason = Reason, 
                                  type = server, 
                                  stacktrace = Stacktrace,
                                  description = "exception in handler module",
                                  soap_req = Soap_req,
                                  handler_state = Handler_s})
        end,
    S#p_state{state = body_done, p2_state = undefined, 
              handler_state = Handler_s2, soap_req = Soap_req2};

%% all events that are part of the body are passed to the body parser.
xml_parser_cb(Event, #p_state{state = parsing_body, 
                              body_parser = B_parser,
                              p2_state = P2_s} = S) ->
    S#p_state{p2_state = B_parser(Event, P2_s)};

%% Done with the parsing.
xml_parser_cb(endDocument, #p_state{soap_req = Req}) ->
    Req;
xml_parser_cb(_, #p_state{state = P_state} = S)
    when P_state /= parsing_body, P_state /= parsing_header ->
    S.

%% As it is this does not add much value. Is it necessary to identify exactly
%% where things go wrong, and if so, what is the right way to do it?
try_header_fun(Fun, Soap_req, Handler_s) ->
    try
        Fun()
    catch
        error:function_clause ->
            {ok, Soap_req, Handler_s};
        Class:Reason:Stacktrace ->
            throw(callback_error(Class, Reason, Soap_req, Handler_s, Stacktrace))
    end.

callback_error(Class, Reason, Soap_req, Handler_s, Stacktrace) ->
    #soap_error{class = Class, 
                reason = Reason, 
                type = server, 
                stacktrace = Stacktrace,
                description = "an unexpected error occcurred",
                soap_req = Soap_req,
                handler_state = Handler_s}.


handle(Parsed_body, Soap_req, Handler_s) ->
    Record_type = element(1, Parsed_body),
    Operations = soap_req:operations(Soap_req),
    Handler = soap_req:handler(Soap_req),
    case lists:keyfind(Record_type, #op.in_type, Operations) of
        false ->
            {fault, soap_fault:fault(client, "Unknown operation", Soap_req), 
             Soap_req, Handler_s};
        #op{operation = Operation} ->
            Handler:Operation(Parsed_body, Soap_req, Handler_s)
    end.

get_header_parser(Handler, Namespace, Soap_req, Handler_s) ->
    Default = fun default_header_parser/3,
    Selector = get_function(Handler, header_parser, 3, Default),
    try 
        {ok, {_, _}, _, _} = 
            Selector(Namespace, Soap_req, Handler_s)
    catch
        error:function_clause ->
            Default(Namespace, Soap_req, Handler_s);
        Class:Reason:Stacktrace ->
            throw(#soap_error{type = server, 
                              description = "Header parser selection error", 
                              stacktrace = Stacktrace,
                              class = Class, reason = Reason})
    end.

parse_event(Parser, Event, State, Type) ->
    try 
        Parser(Event, State)
    catch
        Class:Reason:Stacktrace ->
            %% Presumably failing to parse is a client error (incorrect xml) - but it 
            %% could also be a server error, of course - we don't really know.
            throw(#soap_error{type = client, 
                              description = "Parser error (" ++ Type ++ ")", 
                              stacktrace = Stacktrace,
                              class = Class, reason = Reason})
    end.

encode_soap_resp({error, _, Soap_req, Handler_s} = Soap_resp) ->
    {Handler_s, soap_req:set_resp(Soap_resp, Soap_req)};
encode_soap_resp({raw, _, _, Soap_req, Handler_s} = Soap_resp) ->
    {Handler_s, soap_req:set_resp(Soap_resp, Soap_req)};
encode_soap_resp({Response_code, Body, Soap_req, Handler_s}) ->
    encode_soap_resp({Response_code, Body, [], Soap_req, Handler_s});
encode_soap_resp({Response_code, Body, Headers, Soap_req, Handler_s}) ->
    Soap_req2 = soap_req:set_resp({Response_code, 
                                  encode_part(Body, Soap_req),
                                  [encode_part(H, Soap_req) || H <- Headers],
                                  Soap_req, Handler_s}, Soap_req),
    {Handler_s, Soap_req2}.

encode_part(Part, Soap_req) when is_tuple(Part) ->
    Model = soap_req:model(Soap_req),
    {ok, Xml} = erlsom:write(Part, Model),
    unicode:characters_to_binary(Xml, unicode);
encode_part(Part, _Soap_req) ->
    Part.

default_header_parser(_Namespace, Soap_req, S) ->
    {ok, soap_parsers:skip(undefined), Soap_req, S}.

default_parser(_Namespace, Soap_req, S) ->
    Model = soap_req:model(Soap_req),
    {ok, soap_parsers:data_mapper(Model), Soap_req, S}.

%% default handler, does nothing
skip(_, Req, State) ->
    {ok, Req, State}.

get_function(Module, Function, Arity, Default) ->
    case erlang:function_exported(Module, Function, Arity) of
        true ->
            fun Module:Function/Arity;
        false ->
            Default
    end.

-spec make_exception(Handler::module(), soap_error()) -> 
    soap_handler_response().
make_exception(Handler, #soap_error{class = Class, 
                                    reason = Reason, 
                                    type = Type, 
                                    soap_req = Soap_req, 
                                    handler_state = Handler_state,
                                    stacktrace = Stacktrace,
                                    description = Description} = Error) ->
    try 
        Handler:exception(Class, Reason, Stacktrace, Type, 
                          Description, Soap_req, Handler_state)
    catch
        _:_ ->
            default_exception(Error)
    end.

default_exception(#soap_error{type = Type, 
                              description = Description, 
                              soap_req = Soap_req, 
                              handler_state = Handler_state}) ->
    Code = 
        case Type of
            client -> client;
            server -> server;
            _ -> server
        end,
    {fault, soap_fault:fault(Code, Description, Soap_req), 
     Soap_req, Handler_state}. 
