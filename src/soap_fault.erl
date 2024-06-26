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

%%% 
%%% functions to create soap faults
%%%
-module(soap_fault).

-include("soap.hrl").
-include("soap_fault.hrl").

%% public interface
-export([fault/3]).
-export([fault/4]).
-export([fault/5]).
-export([detail/4]).
-export([code/1]).
-export([code/2]).
-export([code_with_subcode/2]).
-export([code_with_subcode/3]).
-export([reason/2]).

%% used by other modules of the framework
-export([parse_fault/3]).
-export([parse_fault_start/1]).

%% to test:
-export([fault_1_1/4, fault_1_2/4]).

-type soap_req() :: soap:soap_req().
-type tag() :: string().
-type uri() :: string().

-type fault_code_atom() :: soap:soap_fault_code().
-type fault_code() :: fault_code_atom() | fault_code_object().
-export_type([fault_code/0]).

-type fault_string() :: string() | fault_reason() | [fault_reason()].

-type fault_actor() :: string() | undefined.

-opaque fault_detail() :: iodata().
-export_type([fault_detail/0]).

-opaque fault_subcode() :: iodata().
-export_type([fault_subcode/0]).

-opaque fault_code_object() :: #faultcode{}.
-export_type([fault_code_object/0]).

-record(fault_reason, {
    text :: string(),
    lang = "en" :: string()
}).
-opaque fault_reason() :: #fault_reason{}.
-export_type([fault_reason/0]).

-record(pf_state, {
    version :: atom(),
    state :: atom(),
    characters = "" :: string(),
    code :: fault_code_object() | undefined,
    fault_string :: fault_string() | undefined,
    actor :: fault_actor(),
    reasons = [] :: [fault_reason()],
    language :: string() | undefined,
    detail_tag :: {tag(), uri()} | undefined,
    details = [] :: [{tag(), uri(), string()}]
}).

-record(attribute, {
    localName, 
    prefix, 
    uri, 
    value}).

%%% ============================================================================
%%% Exported functions
%%% ============================================================================

%% The simple variant.
-spec fault(fault_code(), fault_string(), soap_req()) -> iolist().
fault(Fault_code, Fault_string, Soap_req) ->
    fault(Fault_code, Fault_string, [], undefined, Soap_req).

-spec fault(fault_code(), fault_string(), [fault_detail()], 
            soap_req()) -> iolist().
fault(Fault_code, Fault_string, Details, Soap_req) ->
    fault(Fault_code, Fault_string, Details, undefined, Soap_req).

-spec fault(fault_code(), fault_string(), [fault_detail()], 
            fault_actor(), soap_req()) -> iolist().
fault(F_code, F_string, F_details, F_actor, Soap_req) ->
    case soap_req:soap_version(Soap_req) of
        Version when Version == '1.1'; Version == undefined ->
            fault_1_1(F_code, F_string, F_details, F_actor);
        '1.2' ->
            fault_1_2(F_code, F_string, F_details, F_actor)
    end.

-spec code(Code::fault_code_atom()) -> fault_code_object().
code(Code) when is_atom(Code) ->
    #faultcode{code = Code}.

-spec code(Uri::string(), Code::string()) -> 
    fault_code_object().
code(Namespace, Code) ->
    #faultcode{uri = xml_string(Namespace), code = xml_string(Code)}.

-spec code_with_subcode(Code::fault_code_atom(), Subcode::fault_code()) -> 
    fault_code_object().
code_with_subcode(Code, Subcode) 
    when is_atom(Code), is_record(Subcode, faultcode) ->
    #faultcode{code = Code,
               subcode = Subcode}.

-spec code_with_subcode(Uri::string(), Code::string(), 
                        Subcode::fault_code()) -> fault_code().
code_with_subcode(Uri, Code, Subcode) ->
    #faultcode{uri = xml_string(Uri), 
               code = xml_string(Code), 
               subcode = Subcode}.

-spec reason(Reason::string(), Language::string()) -> 
    fault_reason().
reason(Reason, Language) ->
    #fault_reason{text = xml_string(Reason), lang = xml_string(Language)}.

-spec detail(Namespace::string(), Prefix::string(), Tag::string(),
             Text::string()) -> fault_detail().
detail(Namespace, Prefix, Tag, Text) ->
    [<<"<">>, Prefix, <<":">>, Tag, <<" xmlns:">>, Prefix, <<"=\"">>, 
     Namespace, <<"\">">>, xml_string(Text), <<"</">>, Prefix, <<":">>, Tag, <<">">>].

-spec parse_fault_start(Version:: '1.1' | '1.2') -> any().
parse_fault_start(Version) ->
    #pf_state{version = Version, 
              state = start}.

-spec parse_fault(Event::erlsom:sax_event(), any(), State::any()) -> any().
parse_fault(Event, Namespaces, #pf_state{version = '1.1'} = State) ->
    parse_fault_1_1(Event, Namespaces, State);
    
parse_fault(Event, Namespaces, #pf_state{version = '1.2'} = State) ->
    parse_fault_1_2(Event, Namespaces, State).

%%% ============================================================================
%%% Internal functions
%%% ============================================================================

%%% ----------------------------------------------------------------------------
%%% Creating faults
%%% ----------------------------------------------------------------------------

fault_1_1(Fault_code, Fault_string, Details, Fault_actor) 
    when is_binary(Fault_string) ->
    fault_1_1(Fault_code, [Fault_string], Details, Fault_actor);
fault_1_1(Fault_code, Fault_string, Details, Fault_actor)
    when is_list(Fault_string) andalso 
         ((length(Fault_string) == 0) orelse not is_tuple(hd(Fault_string))) ->
    Code = fault_code(Fault_code, '1.1'),
    Actor = fault_actor(Fault_actor, '1.1'),
    Xml_string = xml_string(Fault_string),
    [<<"<SOAP-ENV:Fault xmlns=\"\">">>,
     Code,
     <<"<faultstring>">>,
     Xml_string,
     <<"</faultstring>">>,
     Actor,
     fault_detail(Details, '1.1'),
     <<"</SOAP-ENV:Fault>">>].

fault_1_2(Fault_code, Fault_strings, Details, Fault_actor) ->
    Code = fault_code(Fault_code, '1.2'),
    Role = fault_actor(Fault_actor, '1.2'),
    Texts = make_reasons(Fault_strings), 
    [<<"<SOAP-ENV:Fault>">>,
     Code,
     <<"<SOAP-ENV:Reason>">>,
     Texts,
     <<"</SOAP-ENV:Reason>">>,
     Role,
     fault_detail(Details, '1.2'),
     <<"</SOAP-ENV:Fault>">>].

%% somewhat confusingly, Fault_strings can be 
%% - a single #fault_reason{} record
%% - a list of #fault_reason{} records, 
%% - a string (i.e. a list of characters).
make_reasons(Fault_string) 
    when is_tuple(Fault_string) ->
    make_reason(Fault_string); 
make_reasons(Fault_strings) 
    when is_list(Fault_strings) andalso
         ((length(Fault_strings) == 0) orelse is_tuple(hd(Fault_strings))) ->
    [make_reason(Text) || Text <- Fault_strings]; 
make_reasons(Fault_string) ->
    make_reason(#fault_reason{text = Fault_string}).

make_reason(#fault_reason{text = Text, lang = Lang}) ->
    [<<"<SOAP-ENV:Text xml:lang=\"">>, xml_string(Lang), 
     <<"\">">>, xml_string(Text), <<"</SOAP-ENV:Text>">>].

fault_code(Code, Version) when is_atom(Code) ->
    Code_string = fault_code_text(Code, Version),
    case Version of 
        '1.1' ->
            [<<"<faultcode>">>, Code_string, <<"</faultcode>">>]; 
        '1.2' ->
            [<<"<SOAP-ENV:Code><SOAP-ENV:Value>">>, Code_string, 
             <<"</SOAP-ENV:Value></SOAP-ENV:Code>">>]
    end;
fault_code(#faultcode{code = Code}, Version) 
    when Version == '1.1', 
         is_atom(Code) ->
    [<<"<faultcode>">>, fault_code_text(Code, Version), <<"</faultcode>">>]; 
fault_code(#faultcode{uri = Namespace, code = Code}, Version) 
    when Version == '1.1' ->
    [<<"<faultcode xmlns:F_CODE=\"">>, xml_string(Namespace), <<"\">F_CODE:">>,
     xml_string(Code), <<"</faultcode>">>]; 
fault_code(#faultcode{code = Code,
                      subcode = Subcode}, Version) when Version == '1.2' ->
    [<<"<SOAP-ENV:Code><SOAP-ENV:Value>">>, fault_code_text(Code, Version), 
     <<"</SOAP-ENV:Value>">>,
     subcode_text(Subcode),
     <<"</SOAP-ENV:Code>">>].

fault_code_text(Code, Version) when is_atom(Code) ->
  fault_code_text_2(Code, Version);
fault_code_text(Code, Version) when not is_atom(Code) ->
  fault_code_text_2(unicode:characters_to_list(Code), Version).

fault_code_text_2(Code, '1.1') 
    when Code == server;
         Code == "Server" ->
    <<"SOAP-ENV:Server">>; 
fault_code_text_2(Code, '1.2')
    when Code == server;
         Code == "Receiver" ->
    <<"SOAP-ENV:Receiver">>; 
fault_code_text_2(Code, '1.1')
    when Code == client;
         Code == "Client" ->
    <<"SOAP-ENV:Client">>; 
fault_code_text_2(Code, '1.2')
    when Code == client;
         Code == "Sender" ->
    <<"SOAP-ENV:Sender">>; 
fault_code_text_2(Code, _)  %% version 1.2
    when Code == version_mismatch;
         Code == "VersionMismatch" ->
    <<"SOAP-ENV:VersionMismatch">>; 
fault_code_text_2(Code, _)  %% version 1.2
    when Code == must_understand;
         Code == "MustUnderstand" ->
    <<"SOAP-ENV:MustUnderstand">>; 
fault_code_text_2(Code, _)  %% version 1.2
    when Code == data_encoding_unknown;
         Code == "DataEncodingUnknown" ->
    <<"SOAP-ENV:DataEncodingUnknown">>.

subcode_text(#faultcode{uri = Namespace, code = Text}) ->
    [<<"<SOAP-ENV:Subcode><SOAP-ENV:Value xmlns:SUB=\"">>, Namespace, 
     <<"\">SUB:">>, xml_string(Text), 
     <<"</SOAP-ENV:Value></SOAP-ENV:Subcode>">>].

fault_actor(undefined, _) ->
    <<>>;
fault_actor(Actor, '1.1') ->
    [<<"<faultactor>">>, xml_string(Actor), <<"</faultactor>">>];
fault_actor(Actor, '1.2') ->
    [<<"<SOAP-ENV:Role>">>, xml_string(Actor), <<"</SOAP-ENV:Role>">>].

fault_detail([], '1.1') ->
    <<"<detail/>">>;
fault_detail(Details, '1.1') ->
    [<<"<detail>">>, Details, <<"</detail>">>];
fault_detail([], '1.2') ->
    <<"<SOAP-ENV:Detail/>">>;
fault_detail(Details, '1.2') ->
    [<<"<SOAP-ENV:Detail>">>, Details, <<"</SOAP-ENV:Detail>">>].

xml_string(String) ->
    soap_req:xml_string(String).

make_code(String, N_spaces) ->
    case string:tokens(String, ":") of
        [Prefix, Local] ->
            case lists:keyfind(Prefix, 1, N_spaces) of
                false ->
                    #faultcode{uri = "", 
                               code = String};
                {_, Uri} ->
                    #faultcode{uri = Uri, 
                               code = Local}
            end;
        _ ->
            #faultcode{uri = "", 
                       code = String}
    end.

%%% ----------------------------------------------------------------------------
%%% Parsing faults
%%%
%%% These are erlsom:sax callback functions. The reason to use custom parsers 
%%% is that none of the existing erlsom sax parsers make it possible to deal
%%% with qnames ("<SOAP-ENV:Value xmlns:SUB="uri">SUB:code</SOAP-ENV:Value>").
%%% ----------------------------------------------------------------------------

parse_fault_1_1(startDocument, _Namespaces, #pf_state{state = start} = S) ->
    S#pf_state{state = start};
parse_fault_1_1({startElement, ?SOAP_NS, "Fault", _, _}, 
                _Namespaces,
                #pf_state{state = start} = S) ->
    S#pf_state{state = start};
parse_fault_1_1({startElement, _, "faultcode", _, _}, 
                _Namespaces,
                #pf_state{state = start} = S) ->
    S#pf_state{state = code};
parse_fault_1_1({characters, Characters}, 
                _Namespaces,
                #pf_state{characters = String} = S) ->
    S#pf_state{characters = String ++ Characters};
parse_fault_1_1({endElement, _, "faultcode", _},
                Namespaces,
                #pf_state{state = code,
                          characters = String} = S) ->
    S#pf_state{code = make_code(String, Namespaces),
               characters = "",
               state = code_done};
parse_fault_1_1({startElement, _, "faultstring", _, _}, 
                _Namespaces,
                #pf_state{state = code_done} = S) ->
    S#pf_state{state = faultstring};
parse_fault_1_1({endElement, _, "faultstring", _},
                _Namespaces,
                #pf_state{state = faultstring,
                          characters = String} = S) ->
    S#pf_state{fault_string = String,
               characters = "",
               state = faultstring_done};
parse_fault_1_1({startElement, _, "faultactor", _, _}, 
                _Namespaces,
                #pf_state{state = State} = S)
                when State == faultstring_done;
                     State == code_done ->
    S#pf_state{state = faultactor};
parse_fault_1_1({endElement, _, "faultactor", _},
                _Namespaces,
                #pf_state{state = faultactor,
                          characters = String} = S) ->
    S#pf_state{actor = String,
               characters = "",
               state = actor_done};
parse_fault_1_1({startElement, _, "detail", _, _}, 
                _Namespaces,
                #pf_state{state = State} = S)
                when State == faultstring_done;
                     State == code_done;
                     State == actor_done ->
    S#pf_state{state = details};
parse_fault_1_1({startElement, Namespace, Tag, _, _}, 
                _Namespaces,
                #pf_state{state = details} = S) ->
    S#pf_state{state = detail,
               detail_tag = {Tag, Namespace}};
parse_fault_1_1({endElement, Namespace, Tag, _},
                _Namespaces,
                #pf_state{state = detail,
                          details = Details,
                          detail_tag = {Tag, Namespace},
                          characters = String} = S) ->
    S#pf_state{details = [#faultdetail{tag = Tag, 
                                       uri = Namespace, 
                                       text = String} | Details],
               characters = "",
               state = details};
parse_fault_1_1({endElement, _, "detail", _},
                _Namespaces,
                #pf_state{state = details,
                          details = Details} = S) ->
    S#pf_state{details = lists:reverse(Details),
               state = details_done};
parse_fault_1_1({endElement, ?SOAP_NS, "Fault", _},
                _Namespaces,
                #pf_state{state = State} = S)
                when State == faultstring_done;
                     State == code_done;
                     State == actor_done;
                     State == details_done ->
    S#pf_state{state = done};
parse_fault_1_1(endDocument, _Namespaces,
                #pf_state{state = done} = S) ->
    make_record(S).

parse_fault_1_2(startDocument, _Namespaces, #pf_state{state = start} = S) ->
    S#pf_state{state = start};
parse_fault_1_2({startElement, ?SOAP12_NS, "Fault", _, _}, 
                _Namespaces,
                #pf_state{state = start} = S) ->
    S#pf_state{state = start};
parse_fault_1_2({startElement, ?SOAP12_NS, "Code", _, _}, 
                _Namespaces,
                #pf_state{state = start} = S) ->
    S#pf_state{state = code};
parse_fault_1_2({startElement, ?SOAP12_NS, "Value", _, _}, 
                _Namespaces,
                #pf_state{state = code} = S) ->
    S#pf_state{state = code_value};
parse_fault_1_2({startElement, ?SOAP12_NS, "Value", _, _}, 
                _Namespaces,
                #pf_state{state = subcode} = S) ->
    S#pf_state{state = subcode_value};
parse_fault_1_2({characters, Characters}, 
                _Namespaces,
                #pf_state{characters = String} = S) ->
    S#pf_state{characters = String ++ Characters};
parse_fault_1_2({endElement, ?SOAP12_NS, "Value", _},
                Namespaces,
                #pf_state{state = code_value,
                          characters = String} = S) ->
    S#pf_state{code = make_code(String, Namespaces),
               characters = "",
               state = value_done};
parse_fault_1_2({startElement, ?SOAP12_NS, "Subcode", _, _}, 
                _Namespaces,
                #pf_state{state = value_done} = S) ->
    S#pf_state{state = subcode};
parse_fault_1_2({endElement, ?SOAP12_NS, "Value", _},
                Namespaces,
                #pf_state{state = subcode_value,
                          code = Code,
                          characters = String} = S) ->
    S#pf_state{code = Code#faultcode{subcode = make_code(String, Namespaces)},
               characters = "",
               state = value_done};
parse_fault_1_2({endElement, _, "Subcode", _},
                _Namespaces,
                #pf_state{state = value_done} = S) ->
    S#pf_state{state = subcode_done};
parse_fault_1_2({endElement, ?SOAP12_NS, "Code", _},
                _Namespaces,
                #pf_state{state = State} = S) 
    when State == subcode_done;
         State == value_done ->
    S#pf_state{state = code_done};
parse_fault_1_2({startElement, ?SOAP12_NS, "Reason", _, _}, 
                _Namespaces,
                #pf_state{state = code_done} = S) ->
    S#pf_state{state = reasons};
parse_fault_1_2({endElement, ?SOAP12_NS, "Reason", _},
                _Namespaces,
                #pf_state{state = reasons,
                          reasons = Reasons} = S) ->
    S#pf_state{reasons = lists:reverse(Reasons),
               state = reasons_done};
parse_fault_1_2({startElement, ?SOAP12_NS, "Text", _, Attributes}, 
                _Namespaces,
                #pf_state{state = reasons} = S) ->
    Language = 
        case lists:keyfind("lang", #attribute.localName, Attributes) of
            #attribute{prefix = "xml", value = L} ->
                L;
            _Other ->
                undefined
        end, 
    S#pf_state{language = Language, state = text};
parse_fault_1_2({endElement, ?SOAP12_NS, "Text", _},
                _Namespaces,
                #pf_state{state = text,
                          language = Language,
                          reasons = Reasons,
                          characters = String} = S) ->
    S#pf_state{reasons = [#faultreason{language = Language,
                                       text = String} | Reasons],
               characters = "",
               state = reasons};
parse_fault_1_2({startElement, ?SOAP12_NS, "Role", _, _}, 
                _Namespaces,
                #pf_state{state = State} = S)
                when State == reasons_done;
                     State == code_done ->
    S#pf_state{state = role};
parse_fault_1_2({endElement, ?SOAP12_NS, "Role", _},
                _Namespaces,
                #pf_state{state = role,
                          characters = String} = S) ->
    S#pf_state{actor = String,
               characters = "",
               state = role_done};
parse_fault_1_2({startElement, ?SOAP12_NS, "Detail", _, _}, 
                _Namespaces,
                #pf_state{state = State} = S)
                when State == reasons_done;
                     State == code_done;
                     State == role_done ->
    S#pf_state{state = details};
parse_fault_1_2({startElement, Namespace, Tag, _, _}, 
                _Namespaces,
                #pf_state{state = details} = S) ->
    S#pf_state{state = detail,
               detail_tag = {Tag, Namespace}};
parse_fault_1_2({endElement, Namespace, Tag, _},
                _Namespaces,
                #pf_state{state = detail,
                          details = Details,
                          detail_tag = {Tag, Namespace},
                          characters = String} = S) ->
    S#pf_state{details = [#faultdetail{tag = Tag, 
                                       uri = Namespace, 
                                       text = String} | Details],
               characters = "",
               state = details};
parse_fault_1_2({endElement, ?SOAP12_NS, "Detail", _},
                _Namespaces,
                #pf_state{state = details,
                          details = Details} = S) ->
    S#pf_state{details = lists:reverse(Details),
               state = details_done};
parse_fault_1_2({endElement, ?SOAP12_NS, "Fault", _},
                _Namespaces,
                #pf_state{state = State} = S)
                when State == reasons_done;
                     State == code_done;
                     State == role_done;
                     State == details_done ->
    S#pf_state{state = done};
parse_fault_1_2(endDocument, _Namespaces,
                #pf_state{state = done} = S) ->
    make_record(S).

make_record(#pf_state{version = '1.1', code = Code,
                      actor = Actor, details = Details,
                      fault_string = String}) ->
    #soap_fault_1_1{faultcode = Code,
                    faultstring = String,
                    faultactor = Actor,
                    detail = Details};
make_record(#pf_state{version = '1.2', code = Code,
                      actor = Actor, details = Details,
                      reasons = Reasons}) ->
    #soap_fault_1_2{code = Code,
                    reason = Reasons,
                    role = Actor,
                    detail = Details}.
