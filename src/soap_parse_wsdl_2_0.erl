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

%% Deals with the parsing of the WSDL, extracting information from it and
%% translating it to an "interface{}" record.
%%
%% Since this is based on the SOAP 1.1 version, SOAP 1.1 terminolgy is
%% used: endPoint = port, interface = portType.
%%
-module(soap_parse_wsdl_2_0).

-include("soap_wsdl_2_0.hrl").
-include("soap.hrl").

-export([file/4]).
-export([get_services/2]).
-export([get_model/2]).
-export([get_namespaces/2]).

-type option() :: any().
-type namespace_list() :: soap_compile_wsdl:namespace_list().
-type service_list() :: soap_compile_wsdl:service_list().


%%% ============================================================================
%%% Exported functions
%%% ============================================================================

%% Only get the names of the services and associated ports.
%% (used in the dialogue in wsdl2erlang).
-spec get_services(WSDL_file::string(), Options::[option()]) -> 
    service_list().
get_services(Wsdl_file, Options) ->
    get_services([Wsdl_file], Options, []).

%% Only get the "model"
-spec get_model(Wsdl_file::string(), Options::[option()]) ->
    erlsom:model().
get_model(Wsdl_file, Options) ->
    case file(Wsdl_file, "", "", Options) of
        #interface{model = Model} ->
            Model
    end.

%% Only get the namespaces - used to allow the user to assign prefixes
-spec get_namespaces(Wsdl_file::string(), Options::[option()]) -> 
    namespace_list().
get_namespaces(Wsdl_file, Options) ->
    Model = get_model(Wsdl_file, Options),
    Namespace_pairs = erlsom_lib:getNamespacesFromModel(Model),
    %% TODO: it is not clear why 'undefined' should be there at all. 
    lists:usort([Uri || {Uri, _Prefix} <- Namespace_pairs, Uri /= undefined]).


%% Create an 'interface' : an internal representation of the wsdl for
%% a certain service and port.
file(Wsdl_file, Service, Port, Options) ->
    Interface = #interface{service = Service, port = Port},
    parse_wsdls([Wsdl_file], Options, Interface).


%%% ============================================================================
%%% Internal functions
%%% ============================================================================

-spec get_services(WSDL_files::[string()], Options::[option()], 
                   Services::list()) -> service_list().
get_services([], _Options, Services) ->
    Services;
get_services([Wsdl_file | Tail], Options, Acc) ->
    {ok, Wsdl_binary} = get_url_file(Wsdl_file, Options),
    {ok, Wsdl, _} = soap_decode_wsdl_2_0:decode(Wsdl_binary),
    Acc2 = services(Wsdl) ++ Acc,
    Imports = get_imports(Wsdl),
    %% process imports (recursively, 'depth first'),
    %% so that imports in the imported files are
    %% processed as well.
    Acc3 = get_services(Imports, Options, Acc2),
    get_services(Tail, Options, Acc3).

services(#description{service = Services}) ->
    [get_service(Service) || Service <- Services].

get_service(#service{name = Name, choice = EndPoints}) ->
    {Name, [get_port(Port) || Port <- EndPoints, is_record(Port, endpoint)]}.

get_port(#endpoint{name = Name}) ->
    Name.


%% --------------------------------------------------------------------
%% Parse a list of WSDLs and import (recursively)
%% --------------------------------------------------------------------
-spec parse_wsdls(WSDL_files::[string()], Options::[option()], 
                  interface()) -> interface().
parse_wsdls([], _Options, Interface) ->
    Interface;
parse_wsdls([Wsdl_file | Tail], Options, 
            #interface{prefix_count = Pf_count, 
                       imported = Imported} = Interface) ->
    {ok, Wsdl_binary} = get_url_file(Wsdl_file, Options),
    {ok, Wsdl, _} = soap_decode_wsdl_2_0:decode(Wsdl_binary),
    Xsds = get_types(Wsdl, Options),
    %% Now build a list: [{Namespace, Prefix, Xsd}, ...] for all the Xsds 
    %% in the WSDL.
    %% This list is used when a schema includes one of the other schemas.
    %% The AXIS java2wsdl tool generates wsdls that depend on this feature.
    %% Must make sure that nothing gets imported 2x and all schema's get 
    %% a unique prefix.
    Namespace_options = proplists:get_value(namespaces, Options, []),
    {Pf_count2, Import_list} = make_import_list(Xsds, Pf_count, 
                                                Namespace_options),
    Model = Interface#interface.model,
    Model2 = add_schemas(Xsds, Model, Options, Import_list, Imported),
    Ns_list = [{Ns, Pf} || {Ns, Pf, _} <- Import_list],
    Interface2 = Interface#interface{model = Model2, 
                                     prefix_count = Pf_count2,
                                     imported = Imported ++ Ns_list},
    Interface3 = get_operations(Wsdl, Interface2),
    Imports = get_imports(Wsdl),
    %% process imports (recursively, so that imports in the imported files are
    %% processed as well).
    %% For the moment, the namespace is ignored on operations etc.
    %% this makes it a bit easier to deal with imported wsdl's.
    Interface4 = parse_wsdls(Imports, Options, Interface3),
    parse_wsdls(Tail, Options, Interface4).

%% --------------------------------------------------------------------
%% build a list: [{Namespace, Prefix, Xsd}, ...] for all the Xsds in 
%% the WSDL.
%% This list is used when a schema includes one of the other schemas.
%% The AXIS java2wsdl tool generates wsdls that depend on this feature.
%% Also the SalesForce API uses it.
%% --------------------------------------------------------------------
-spec make_import_list(any(), any(), 
      [{Uri::string(), Prefix::string() | undefined}]) -> any().
make_import_list(Xsds, Count, Namespaces) ->
    make_import_list(Xsds, Count, Namespaces, []).

make_import_list([], Count, _Namespaces, Acc) ->
    {Count, lists:reverse(Acc)};
make_import_list([Xsd | T], Count, Namespaces, Acc) ->
    Uri = erlsom_lib:getTargetNamespaceFromXsd(Xsd), 
    New_acc = case Uri of 
                  undefined -> %% if the schema only imports another one
                      Acc;
                  _ ->
                      Prefix = proplists:get_value(Uri, Namespaces, undefined),
                      [{Uri, Prefix, Xsd} | Acc]
              end,
  make_import_list(T, Count + 1, Namespaces, New_acc).

%% --------------------------------------------------------------------
%% compile each of the schemas, and add it to the model.
%% Returns Model
%% --------------------------------------------------------------------
add_schemas([], AccModel, _Options, _ImportList, _Imported) ->
    AccModel;
add_schemas([Xsd| Tail], AccModel, Options, ImportList, Imported) ->
    Include_any_attribs = proplists:get_value(include_any_attribs, Options, 
                                              false),
    ErlsomOptions = proplists:get_value(erlsom_options, Options, []),
    Tns = erlsom_lib:getTargetNamespaceFromXsd(Xsd),  
    Prefix = 
        case lists:keyfind(Tns, 1, ImportList) of
            {_, P, _} -> P;
            _ -> ""
        end,
    {ok, Model} =
         erlsom_compile:compile_parsed_xsd(Xsd,
                             [{include_files, ImportList}, 
                              {already_imported, Imported}, 
                              {include_any_attribs, Include_any_attribs},
                              {prefix, Prefix} | ErlsomOptions]),
    {Model2, Imported2} = 
        case AccModel of
            undefined -> 
                {Model, [{Tns, Prefix} | Imported]};
            _ -> 
                {erlsom:add_model(AccModel, Model), [{Tns, Prefix} | Imported]}
        end,
    add_schemas(Tail, Model2, Options, ImportList, Imported2).


get_types(#description{types = Types}, Options) ->
    #types{'#any' = Xsds} = Types,
    [get_xsd(Xsd, Options) || Xsd <- Xsds].

get_xsd(Xsd, _) when element(1, Xsd) == schema ->
    Xsd;
get_xsd({importType, _, _, _, Location, _}, Options) ->
    {ok, Xsd_binary} = get_url_file(Location, Options),
    {ok, Xsd, _} = erlsom:scan(Xsd_binary, erlsom_parseXsd:xsdModel()),
    Xsd.


get_imports(#description{import = undefined}) ->
    [];
get_imports(#description{import = Imports}) ->
    [Location || #import{location = Location} <- Imports].

get_operations(#description{service = Services} = Wsdl, 
               #interface{service = Service, port = Port} = Interface) ->
    case lists:keyfind(Service, #service.name, Services) of
        false ->
            Interface;
        #service{choice = Endpoints_and_more} ->
            Endpoints = [E || E <- Endpoints_and_more, is_record(E, endpoint)],
            case lists:keyfind(Port, #endpoint.name, Endpoints) of
                false ->
                    Interface;
                #endpoint{binding = Binding, address = Url} ->
                    Binding_str = erlsom_lib:localName(Binding),
                    Interface2 = get_ops_from_binding(Wsdl, 
                                 Interface#interface{binding = Binding_str}),
                    Interface2#interface{url = Url}
            end
    end.

get_ops_from_binding(#description{binding = Bindings} = Wsdl, 
                     #interface{binding = Binding} = Interface) ->
    case lists:keyfind(Binding, #binding.name, Bindings) of
        false ->
            Interface;
        #binding{type = Type, choice = Operations_and_more,
                 interface = Wsdl_interface} ->
              Operations = [Op || Op <- Operations_and_more, 
                                        is_record(Op, bindingOperation)],
              {Soap_version, Soap_ns} = soap_version(Type),
              Interface_str = erlsom_lib:localName(Wsdl_interface),
              Interface2 = 
                  get_ops_from_port_type(Wsdl, 
                                         Interface#interface{
                                             port_type = Interface_str,
                                             version = Soap_version,
                                             soap_ns = Soap_ns}),
              get_ops_from_binding2(Operations, Interface2)
    end.

soap_version("http://www.w3.org/2004/08/wsdl/soap12") ->
    {'1.2', ?SOAP12_NS};
soap_version("http://www.w3.org/ns/wsdl/soap") ->
    {'1.1', ?SOAP_NS}.


%% Need to get the soapAction for each operation from the binding.
%% Note that an empty (but quoted) value must be used if no value
%% is specified by the binding (Basic Profile 1.1, R1109).
get_ops_from_binding2(Operations, #interface{ops = Ops} = Interface) ->
    Ops2 = [get_op_from_binding(Op, Operations) || Op <- Ops],
    Interface#interface{ops = Ops2}.

get_op_from_binding(#op{name = Name} = Op, Operations) ->
    case find_op(Name, Operations) of
        false ->
            Op;
        #bindingOperation{anyAttribs = Extensions} ->
            Op#op{soap_action = get_action(Extensions)}
    end.

find_op(_Name, []) ->
    false;
find_op(Name, [#bindingOperation{ref = #qname{localPart = Name}} = Op | _]) ->
    Op;
find_op(Name, [_ | T]) ->
    find_op(Name, T).

get_action([]) ->
    "";
get_action([{{"action", "http://www.w3.org/ns/wsdl/soap"}, Value} | _]) ->
    Value;
get_action([_ | T]) ->
    get_action(T).


get_ops_from_port_type(#description{interface = Interfaces}, 
                       #interface{port_type = Port_type, ops = Ops} = Interface) ->
    case lists:keyfind(Port_type, #wsdl_interface.name, Interfaces) of
        false ->
            Interface;
        #wsdl_interface{choice = Operations_and_more} ->
            Operations = [Op || Op <- Operations_and_more, 
                          is_record(Op, interfaceOperation)],
            case process_ops(Operations, Interface) of
                [] ->
                    {error, "No request-response or one-way operations found"};
                Result  ->
                    Interface#interface{ops = Ops ++ Result}
            end
    end.

process_ops(Operations, Interface) ->
    lists:flatten([process_op(Op, Interface) || Op <- Operations]).

process_op(#interfaceOperation{name = Name, 
                               choice = Messages,
                               pattern = Pattern},
           #interface{model = Model}) ->
    Op_type = op_type(Pattern),
    Op1 = #op{op_type = Op_type,
              name = Name,
              operation = list_to_atom(Name)},
    case Op_type of
        undefined ->
            [];
        request_response ->
            Op1#op{in_type = input_type(Messages, Model),
                   out_type = output_type(Messages, Model)};
        notification ->
            Op1#op{in_type = input_type(Messages, Model)}
    end.

input_type(Messages, Model) ->
    [Input] = [M || M <- Messages, is_record(M, 'interfaceOperation-input')],
    message_type(Input#'interfaceOperation-input'.element, Model).

output_type(Messages, Model) ->
    [Output] = [M || M <- Messages, is_record(M, 'interfaceOperation-output')],
    message_type(Output#'interfaceOperation-output'.element, Model).

message_type(Element, Model) ->
    LocalPart = erlsom_lib:localName(Element),
    Uri = erlsom_lib:getUriFromQname(Element),
    Prefix = erlsom_lib:getPrefixFromModel(Model, Uri),
    Element_name = 
        case Prefix of 
            undefined ->
                LocalPart;
            "" ->
                LocalPart;
            _ -> 
                Prefix ++ ":" ++ LocalPart
        end,
    type_for_element(list_to_atom(Element_name), Model).

type_for_element(Element, Model) ->
    erlsom_lib:getTypeFromElement(Element, Model).

op_type("http://www.w3.org/2004/03/wsdl/in-out") ->
    request_response;
op_type("http://www.w3.org/ns/wsdl/in-out") ->
    request_response;
op_type("http://www.w3.org/2004/03/wsdl/in-only") ->
    notification;
op_type("http://www.w3.org/ns/wsdl/in-only") ->
    notification;
op_type(_) ->
    undefined.

%%% --------------------------------------------------------------------
%%% Get a file from an URL spec.
%%% --------------------------------------------------------------------
get_url_file("http://"++_ = URL, _Options) ->
    case httpc:request(URL) of
        {ok,{{_HTTP,200,_OK}, _Headers, Body}} ->
            {ok, Body};
        {ok,{{_HTTP,_RC,_Emsg}, _Headers, _Body}} ->
            {error, "failed to retrieve: "++URL};
        {error, _Reason} ->
            {error, "failed to retrieve: "++URL}
    end;
get_url_file("https://"++_ = URL, _Options) ->
    case httpc:request(URL) of
        {ok,{{_HTTP,200,_OK}, _Headers, Body}} ->
            {ok, Body};
        {ok,{{_HTTP,_RC,_Emsg}, _Headers, _Body}} ->
            {error, "failed to retrieve: "++URL};
        {error, _Reason} ->
            {error, "failed to retrieve: "++URL}
    end;
get_url_file("file://" ++ F_name, Options) ->
    File_name = 
        case proplists:get_value(include_path, Options) of
            undefined ->
                F_name;
            Path ->
                filename:join(Path, F_name)
        end,
    case file:read_file(File_name) of
        {ok, Bin} ->
            {ok, Bin};
        _ ->
           {error, "failed to read: " ++ F_name}
    end;
get_url_file(F_name, Options) ->
    get_url_file("file://" ++ F_name, Options).
