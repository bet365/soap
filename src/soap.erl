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
%%% Interface (facade) for the soap framework.
%%% 
-module(soap).
-export([wsdl2erlang/1, wsdl2erlang/2]).
-export([make_test_client/1, make_test_client/2]).
-export([erlang2wsdl/3, erlang2wsdl/4]).
-export([start_server/1, start_server/2]).
-export([stop_server/1, stop_server/2]).

%%% ============================================================================
%%% Types
%%%
%%% The framework implements 5 interfaces:
%%% 1 - client implementation <--> client side of the framework. 
%%%     This interface is relevant for the programmer who wants to use the 
%%%     SOAP service.
%%% 2 - client side of the framework <--> the http client.
%%%     This interface is relevant for a programmer who wants to use the
%%%     framework with an HTTP client that is not yet supported.
%%% 3 - the actual SOAP interface "on the wire", http client <--> the http 
%%%     server. 
%%% 4 - HTTP server <--> server side of the framework. 
%%%     This interface is relevant for a programmer who wants to use the 
%%%     framework with an HTTP server that is not yet supported.
%%% 5 - server side of the framework <--> server implementation (provided by 
%%%     the user/programmer who implements the service).
%%%     This interface is relevent for the programmer who needs to implement 
%%%     the SOAP service.
%%%
%%% Below follows an overview of the types that are exchanged on the relevant 
%%% interfaces.
%%% ============================================================================

%% Some basic types 
-type http_status_code() :: integer().
-export_type([http_status_code/0]).

-type header_name() :: string().
-type header_value() :: string().
-type http_body() :: iolist().
-type http_header() :: {header_name(), header_value()}.
-export_type([http_header/0]).


-type attachment_body() :: binary().
-type soap_attachment() :: {[http_header()], attachment_body()}.
-export_type([soap_attachment/0]).

-type soap_header() :: tuple() | iodata().
-export_type([soap_header/0]).

-type function_name() :: atom().

%%% ----------------------------------------------------------------------------
%%% Interface 1 -
%%% Types used on the client side, on the interface to call a soap 
%%% operation.
%%% ----------------------------------------------------------------------------

%% Invoking a soap operation returns a soap_response()
-type soap_response(Body) :: 
    {ok, http_status_code(), [http_header()], [soap_header()], 
         Body, [soap_attachment()], http_body()} | 
    {fault, http_status_code(), [http_header()], [soap_header()], 
            soap_fault(), [soap_attachment()], http_body()} |
    {error, soap_response_error(), http_body()}.
-export_type([soap_response/1]).

-type soap_fault() :: iolist().

-type soap_response_error() :: 
    {client, any()} | %% problem processing the request on the client side
    {server, http_status_code(), [http_header()]}. %% Server sent HTTP error

%%% ----------------------------------------------------------------------------
%%% Interface 2 -
%%% Types used on the client side, on the interface between the framework and 
%%% the HTTP client.
%%% ----------------------------------------------------------------------------

-type ok_http_response() :: {ok, http_status_code(), [http_header()],
                                                      http_body()}.
-type error_http_response() :: {error, any()}.
-type http_response() :: ok_http_response() | error_http_response().
-export_type([http_response/0]).

%%% ----------------------------------------------------------------------------
%%% Interface 4 - 
%%% Types used on the server side, on the interface between the soap framework
%%% and the HTTP server
%%% ----------------------------------------------------------------------------

%% the server_req() is whatever is used by the HTTP server to keep track of it's
%% state.
-type server_req() :: any().
-export_type([server_req/0]).

%% This is the type of the response from the framework to the http server 
%% integration module. The effect should be that an HTTP response based on this 
%% information is sent to the client.
-type server_http_response() :: {ok, http_status_code(), [http_header()], 
                          http_body(), server_req()}.
-export_type([server_http_response/0]).

%%% ----------------------------------------------------------------------------
%%% Interface 5 - 
%%% Types used on the server side, on the interface between implementation 
%%% (handler module) and the soap framework
%%% ----------------------------------------------------------------------------

%% Used to pass information between consecutive calls to the handler module, 
%% to be used by the implementation.
-type soap_handler_state() :: any().
-export_type([soap_handler_state/0]).

%% Used to pass information between consecutive calls to the handler module, 
%% opaque for the implementation. Used by the framework, or by the 
%% implementation of the operations via accessor functions from the
%% soap_req module.
%%
-type soap_req() :: soap_req:soap_req().
-export_type([soap_req/0]).

%% The framework translates the XML message body to a record. The
%% definition of the records depends on the types in the WSDL.
-type soap_body(Body) :: Body | iolist().
-export_type([soap_body/1]).

%% The implementation of the operation on the server side (in the handler 
%% module) must return a soap_handler_response()
-type soap_handler_response(Body) :: 
    {ok, soap_body(Body), soap_req(), soap_handler_state()} |
    {ok, soap_body(Body), [soap_header()], soap_req(), soap_handler_state()} |
    {fault, soap_body(Body), soap_req(), soap_handler_state()} |
    {fault, soap_body(Body), [soap_header()], soap_req(), soap_handler_state()} |
    {error, http_status_code(), soap_req(), soap_handler_state()} |
    {raw, http_status_code(), binary(), soap_req(), soap_handler_state()}.
-export_type([soap_handler_response/1]).

-type method() :: string().
-type media_type() :: string().
-type protocol_error() :: {method_not_allowed, method()} |
                          {unsupported_media_type, media_type()}.
-export_type([protocol_error/0]).

%% Codes passed to the "exception" callback. 
%% They correspond to the SOAP Fault Codes from the spec.
%% soap_fault:make_fault will translate them to the appropriate
%% string in the fault message.
-type soap_fault_code() :: server | %% "Server" (SOAP 1.1) or "Sender" (1.2)
                           client | %% "Client" (SOAP 1.1) or "Receiver" (1.2)
                           version_mismatch | %% "VersionMismatch"
                           must_understand | %% "MustUnderstand"
                           data_encoding_unknown. %% "DataEncodingUnknown"
-export_type([soap_fault_code/0]).

%%% ----------------------------------------------------------------------------
%%% Options 
%%% ----------------------------------------------------------------------------

-type wsdl2erlang_option() :: {http_client, atom()} | 
                              {http_options, any()} |
                              {http_server, atom()} |
                              {automatic_prefixes, boolean()} |
                              {attachments, boolean()} |
                              {test_values, boolean()} |
                              {generate_tests, none | client | server | both} |
                              {module, string()} |
                              {generate, client | server | both} |
                              {service, string()} |
                              {port, string()}.
-export_type([wsdl2erlang_option/0]).

-type test_client_option() :: {hrl_name, string()} | 
                              {test_module, atom()} |
                              {soap_options, any()} |
                              {soap_headers, any()}. 

-type erlang2wsdl_option() :: {target_namespace, string()}.

-type server_option() :: any().

%%% ============================================================================
%%% Exported functions
%%% ============================================================================

-spec start_server(module()) -> any().
start_server(Server) ->
    start_server(Server, []).

-spec start_server(module(), [server_option()]) -> any().
start_server(Server, Options) ->
    Http_server = soap_interface:http_server(Server:interface()),
    soap_server_util:start(Server, Http_server, Options).

-spec stop_server(module()) -> any().
stop_server(Server) ->
    stop_server(Server, []).

-spec stop_server(module(), [server_option()]) -> any().
stop_server(Server, Options) ->
    Http_server = soap_interface:http_server(Server:interface()),
    soap_server_util:stop(Server, Http_server, Options).

%% Generate a number of Erlang modules from a WSDL
-spec wsdl2erlang(Filename::string()) -> ok | {error, any()}.
wsdl2erlang(File) ->
    wsdl2erlang(File, []).

-spec wsdl2erlang(Filename::string(), [wsdl2erlang_option()]) -> 
    ok | {error, any()}.
wsdl2erlang(File, Options) ->
    Base_name = filename:rootname(filename:basename(File), ".wsdl"),
    Default_client_name = Base_name ++ "_client",
    Client_name = proplists:get_value(client_name, Options, 
                                      Default_client_name),
    Default_server_name = Base_name ++ "_server",
    Server_name = proplists:get_value(server_name, Options, 
                                      Default_server_name),
    Hrl_name = proplists:get_value(hrl_name, Options, Base_name),
    %% Do we need to create client, server or both?
    Generate = get_value(Options, generate, "What must be generated?", 
                         [client, server, both]),
    Make_client = (Generate == client) or (Generate == both),
    Make_server = (Generate == server) or (Generate == both),

    %% generate test stubs and skeletons?
    Generate_tests = 
        case get_value_relaxed(Options, generate_tests, 
                       "\nDo you want to generate test stubs/skeletons?",
                       [no, 
                        "yes, client only",
                        "yes, server only",
                        "yes, client and server"]) of
            no -> none;
            "yes, client only" -> client;
            "yes, server only" -> server;
            "yes, client and server" -> both;
            Other when Other == client; Other == server; 
                       Other == both; Other == none -> Other
        end,

    Need_http_server = Make_server or 
                       (Generate_tests == both) or 
                       (Generate_tests ==  server),

    %% which HTTP server must be used?
    Http_server_options = case Need_http_server of
        true -> 
            Server_choice = 
                case get_value_relaxed(Options, http_server, 
                                       "\nWhich http server must be used?", 
                                       [cowboy_v1, cowboy_v2, inets, mochiweb]) of
                    inets -> soap_server_inets;
                    cowboy_v1 -> soap_server_cowboy_1;
                    cowboy_v2 -> soap_server_cowboy_2;
                    mochiweb -> soap_server_mochiweb;
                    Other_server -> Other_server
                end,
            [{http_server, Server_choice}, {server_name, Server_name}];
        false -> []
    end,

    Need_http_client = Make_client or 
                       (Generate_tests == both) or 
                       (Generate_tests ==  client),

    %% which HTTP client must be used?
    Http_client_options = case Need_http_client of
        true -> 
            Client_choice = 
                case get_value_relaxed(Options, http_client, 
                                       "\nWhich http client must be used?", 
                                       [ibrowse, inets]) of
                    inets -> soap_client_inets;
                    ibrowse -> soap_client_ibrowse;
                    Other_client -> Other_client
                end,
            [{http_client, Client_choice}, {client_name, Client_name}];
        false -> []
    end,

    %% For which service and port should the client and/or server be?
    Services = soap_compile_wsdl:get_services(File, Options),
    Service_names = [Name || {Name, _} <- Services],
    Service = get_value(Options, service, 
                        "\nWhich service must be implemented?",
                        Service_names), 
    Port_names = proplists:get_value(Service, Services),
    Port = get_value(Options, port, "\nWhich port must be implemented?",
                     Port_names), 
    Namespaces = soap_compile_wsdl:get_namespaces(File, Options),
    Prefixes = get_prefixes(Namespaces, Options),
    %% The default for 'strict' differs between soap and erlsom.
    %% For reasons of backwards compatibility the Erlsom `strict` option
    %% can be set in 2 ways: as an `erlsom_option` and as a separate
    %% explicit option (the explicit option "wins" if both variants are 
    %% provided).
    ErlsomOpts = proplists:get_value(erlsom_options, Options, []),
    Strict1 = proplists:get_value(strict, ErlsomOpts, true),
    Strict2 = proplists:get_value(strict, Options, Strict1),
    ErlsomOpts2 = [Option 
                   || {Key, _} = Option <- ErlsomOpts, Key /= strict],
    Remove = [generate, http_server, http_client, port, service, namespaces,
              client_name, server_name, hrl_name, erlsom_options, strict,
              generate_tests],
    Other_options = [Option || {Key, _} = Option <- Options, 
                                          not(lists:member(Key, Remove))],
    Options2 = lists:flatten([{generate, Generate}, {namespaces, Prefixes}, 
                              {generate_tests, Generate_tests},
                              Http_server_options, Http_client_options, 
                              {erlsom_options, [{namespaces, Prefixes}, 
                                                {strict, Strict2} 
                                                | ErlsomOpts2]}
                              | Other_options]),
    soap_compile_wsdl:file(File, Service, Port, Options2, Hrl_name).

%% Generate a module with test functions (using default values) for every 
%% operation.
%%
%% The input parameter must be a client module, generated by 
%% 'soap:erlang2wsdl()'. The 'interface()' function from the client module 
%% is used to get access to information about the service.
%%
%% The generated test_client module includes the .hrl file that is generated 
%% by 'soap:erlang2wsdl()'. The default assumption is that the client module 
%% has the default '_client' postfix, so that the name of the .hrl file can be 
%% derived from the name of the client module. If that is not the case, the 
%% name of the .hrl file can be provided using the {hrl_name, Filename} 
%% option.
-spec make_test_client(Module::atom()) -> {ok, [function_name()]}.
make_test_client(Module) ->
    make_test_client(Module, []).

-spec make_test_client(Module::atom(), [test_client_option()]) ->
    {ok, [function_name()]}.
make_test_client(Module, Options) ->
    soap_test_module:from_client(Module, Options).

%% Generate a WSDL from a .hrl file that contains specifications of the
%% operations and the used types.
-spec erlang2wsdl(Hrl_file::string(), Service_name::string(), Url::string()) -> 
    ok.
erlang2wsdl(Hrl_file, Servce_name, Url) ->
    erlang2wsdl(Hrl_file, Servce_name, Url, []).

-spec erlang2wsdl(Hrl_file::string(), Service_name::string(), Url::string(), 
    [erlang2wsdl_option()]) -> ok.
erlang2wsdl(Hrl_file, Service_name, Url, Options) ->
    soap_hrl2wsdl:file(Hrl_file, Service_name, Url, Options).

%%% ============================================================================
%%% Internal functions
%%% ============================================================================

%% Every namespace must have a different prefix (1 may be "empty")
get_prefixes(Uris, Options) ->
    Automatic = proplists:get_value(automatic_prefixes, Options, false),
    Uris2 = lists:delete("http://www.w3.org/2001/XMLSchema", Uris),
    Specified = proplists:get_value(namespaces, Options, []),
    Prefix_fun = 
        case Automatic of
            true ->
                fun automatic_prefix/2;
            false ->
                fun get_prefix/2
        end,
    {Prefixes, _Count} = lists:foldl(Prefix_fun, {Specified, 0}, Uris2),
    Prefixes.

automatic_prefix(Uri, {Pairs, Count} = Acc) ->
    case proplists:get_value(Uri, Pairs, none) of
        none ->
            Next_prefix = lists:flatten(io_lib:format("P~p", [Count])),
            {[{Uri, Next_prefix} | Pairs], Count + 1};
        _ ->
            Acc
    end.


get_prefix(Uri, {Uri_prefix_pairs, Count} = Acc) ->
    case proplists:get_value(Uri, Uri_prefix_pairs, none) of
        none ->
            add_prefix(Uri, Uri_prefix_pairs, Count);
        _ ->
            Acc
    end.

add_prefix(Uri, Pairs, Count) ->
    Prompt = "\nSelect a prefix for URI " ++ Uri,
    Allow_undefined = (lists:keyfind(undefined, 2, Pairs) == false),
    Undefined_option = "No prefix",
    Specify_option = "Specify a custom prefix",
    Default_option = lists:flatten(io_lib:format("P~p", [Count])),
    Options = 
        case Allow_undefined of
            true ->
                [Undefined_option, Default_option, Specify_option];
            false ->
                [Specify_option, Default_option]
        end,
    case select_option(Options, Prompt) of
        Undefined_option ->
            {[{Uri, undefined} | Pairs], Count};
        Default_option ->
            {[{Uri, Default_option} | Pairs], Count + 1};
        Specify_option ->
            {[{Uri, custom_prefix(Pairs)} | Pairs], Count}
    end.

custom_prefix(Used_pairs) ->
    Input = io:get_line("Enter a prefix: "),
    Prefix = string:left(Input, length(Input) - 1),
    case Prefix of
        "" ->
            custom_prefix(Used_pairs);
        _ ->
            case lists:keyfind(Prefix, 1, Used_pairs) of
                false -> Prefix;
                _ -> custom_prefix(Used_pairs)
            end
    end.


%% accept only values from the list
get_value(Options, Key, Prompt, Allowed) ->
    case proplists:get_value(Key, Options) of
        undefined ->
            select_option(Allowed, Prompt);
        Value ->
            case lists:member(Value, Allowed) of
                true ->
                    Value;
                false ->
                    throw({error, "invalid value for option " ++ 
                           atom_to_list(Key)})
            end
    end.

%% accept any value that is provided by the user
get_value_relaxed(Options, Key, Prompt, Allowed) ->
    case proplists:get_value(Key, Options) of
        undefined ->
            select_option(Allowed, Prompt);
        Value ->
            Value
    end.

select_option([Value], _) ->
    Value;
select_option(Values, Prompt) ->
    io:format("~s~n", [Prompt]),
    Options = lists:zip(lists:seq(1, length(Values)), Values),
    lists:foreach(fun({Nr, Name}) -> 
                      io:format("~p: ~s~n", [Nr, Name]) 
                  end, Options),
    ValidInput = [{integer_to_list(Nr), Name} || {Nr, Name } <- Options],
    get_input(ValidInput).

get_input(ValidInput) ->
    Nr = io:get_line("Select a number: "),
    Number = string:left(Nr, length(Nr) - 1),
    case lists:keyfind(Number, 1, ValidInput) of
        false -> get_input(ValidInput);
        {_, Value} -> Value
    end.
