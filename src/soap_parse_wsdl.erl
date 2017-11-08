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

%%% Deals with the parsing of the WSDL, extracting information from it and
%%% translating it to an "interface{}" record.
-module(soap_parse_wsdl).

-include("soap_wsdl_1_1.hrl").
-include("soap.hrl").

-export([file/4]).
-export([get_services/2]).
-export([get_model/2]).
-export([get_namespaces/2]).

-type option() :: any().
-type service_name() :: string().
-type port_name() :: string().
-type uri() :: string().
-type prefix() :: string().
-type service_list() :: [{service_name(), [port_name()]}].


%% ---------------------------------------------------------------------------
%% Only get the names of the services and ports.
%% ---------------------------------------------------------------------------
-spec get_services(WSDL_file::string(), Options::[option()]) -> 
    service_list().
get_services(Wsdl_file, Options) ->
    get_services([Wsdl_file], Options, []).

%% ---------------------------------------------------------------------------
%% Only get the "model"
%% ---------------------------------------------------------------------------
-spec get_model(Wsdl_file::string(), Options::[option()]) ->
    erlsom:model().
get_model(Wsdl_file, Options) ->
    case file(Wsdl_file, "", "", Options) of
        #interface{model = Model} ->
            Model
    end.

%% ---------------------------------------------------------------------------
%% Only get the namespaces - used to allow the user to assign prefixes
%% ---------------------------------------------------------------------------
-spec get_namespaces(Wsdl_file::string(), Options::[option()]) -> 
    [{uri(), prefix()}].
get_namespaces(Wsdl_file, Options) ->
    case get_model(Wsdl_file, Options) of
        undefined ->
            [];
        Model ->
            Namespace_pairs = erlsom_lib:getNamespacesFromModel(Model),
            lists:usort([Uri || {Uri, _Prefix} <- Namespace_pairs, 
                                                  Uri /= undefined])
    end.

%% ---------------------------------------------------------------------------
%% Create an 'interface' : an internal representation of the wsdl for
%% a certain service and port.
%% ---------------------------------------------------------------------------
file(Wsdl_file, Service, Port, Options) ->
    Interface =  parse_wsdls([Wsdl_file], 
                             Options,
                             #interface{service = Service, port = Port}),
    Interface2 = case Interface of
                     #interface{style = "rpc"} ->
                         wrap_rpc_types(Interface, Options);
                     _ ->
                         Interface
                 end,
    clean_up(Interface2).

%%% ---------------------------------------------------------------------------
%%% Internal functions
%%% ---------------------------------------------------------------------------

%% ---------------------------------------------------------------------------
%% Parse a list of WSDLs and process (recursively)
%% ---------------------------------------------------------------------------
-spec get_services(WSDL_files::[string()], Options::[option()], 
                   Services::list()) -> service_list().
get_services([], _Options, Services) ->
    Services;
get_services([Wsdl_file | Tail], Options, Acc) ->
    {ok, Wsdl_binary} = get_url_file(Wsdl_file),
    {ok, Wsdl, _} = soap_decode_wsdl_1_1:decode(Wsdl_binary),
    Acc2 = services(Wsdl) ++ Acc,
    Imports = get_imports(Wsdl),
    %% process imports (recursively, 'depth first'),
    %% so that imports in the imported files are
    %% processed as well.
    Acc3 = get_services(Imports, Options, Acc2),
    get_services(Tail, Options, Acc3).

services(#'wsdl:definitions'{service = Services}) ->
    [get_service(Service) || Service <- Services].

get_service(#'wsdl:service'{name = Name, port = Ports}) ->
    {Name, [get_port(Port) || Port <- Ports]}.

get_port(#'wsdl:wsdl_port'{name = Name}) ->
    Name.


%% ---------------------------------------------------------------------------
%% Parse a list of WSDLs and import (recursively)
%% ---------------------------------------------------------------------------
-spec parse_wsdls(WSDL_files::[string()], Options::[option()], 
                  interface()) -> interface().
parse_wsdls([], _Options, Interface) ->
    Interface;
parse_wsdls([Wsdl_file | Tail], Options, 
            #interface{prefix_count = Pf_count, 
                       target_ns = Target_ns,
                       imported = Imported} = Interface) ->
    {ok, Wsdl_binary} = get_url_file(Wsdl_file),
    {ok, Wsdl, _} = soap_decode_wsdl_1_1:decode(Wsdl_binary),
    Xsds = get_types(Wsdl),
    %% Now we need to build a list: [{Namespace, Prefix, Xsd}, ...] for
    %% all the Xsds in the WSDL.
    %% This list is used when a schema includes one of the other schemas.
    %% The AXIS java2wsdl tool generates wsdls that depend on this feature.
    %% Must make sure that nothing gets imported 2x and all schema's get 
    %% a unique prefix.
    Namespace_options = proplists:get_value(namespaces, Options, []),
    {Pf_count2, Import_list} = make_import_list(Xsds, Pf_count, Namespace_options),
    Model = Interface#interface.model,
    Model2 = add_schemas(Xsds, Model, Options, Import_list, Imported),
    Ns_list = [{Ns, Pf} || {Ns, Pf, _} <- Import_list],
    Interface2 = Interface#interface{model = Model2, 
                                     target_ns = case Target_ns of
                                                     undefined ->
                                                         get_tns(Wsdl);
                                                     _ ->
                                                         Target_ns
                                                 end,
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

%% ----------------------------------------------------------------------------
%% build a list: [{Namespace, Prefix, Xsd}, ...] for all the Xsds in the WSDL.
%% This list is used when a schema includes one of the other schemas.
%% The AXIS java2wsdl tool generates wsdls that depend on this feature.
%% Also the SalesForce API uses it.
%% ----------------------------------------------------------------------------
-spec make_import_list(any(), any(), 
            [{Uri::string(), Prefix::string() | undefined}]) -> any().
make_import_list(Xsds, Count, Namespaces) ->
    make_import_list(Xsds, Count, Namespaces, []).

make_import_list(undefined, Count, _Namespaces, Acc) ->
    {Count, lists:reverse(Acc)};
make_import_list([], Count, _Namespaces, Acc) ->
    {Count, lists:reverse(Acc)};
make_import_list([Xsd | T], Count, Namespaces, Acc) ->
    Uri = erlsom_lib:getTargetNamespaceFromXsd(Xsd), 
    New_acc = 
        case Uri of 
            undefined -> %% if the schema only imports another one
                Acc;
            _ ->
                Prefix = proplists:get_value(Uri, Namespaces, undefined), 
                [{Uri, Prefix, Xsd} | Acc]
        end,
    make_import_list(T, Count + 1, Namespaces, New_acc).

%% ----------------------------------------------------------------------------
%% compile each of the schemas, and add it to the model.
%% Returns Model
%% ----------------------------------------------------------------------------
add_schemas(undefined, AccModel, _Options, _ImportList, _Imported) ->
        AccModel;
add_schemas([], AccModel, _Options, _ImportList, _Imported) ->
        AccModel;
add_schemas([Xsd| Tail], AccModel, Options, ImportList, Imported) ->
    Include_any_attribs = 
        proplists:get_value(include_any_attribs, Options, false),
    ErlsomOptions = proplists:get_value(erlsom_options, Options, []),
    Tns = erlsom_lib:getTargetNamespaceFromXsd(Xsd),    
    Prefix = 
        case lists:keyfind(Tns, 1, ImportList) of
            {_, P, _} ->
                P;
            _ ->
                ""
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


get_types(#'wsdl:definitions'{types = Types}) ->
    #'wsdl:types'{choice = Xsds} = Types,
    Xsds.

get_tns(#'wsdl:definitions'{targetNamespace = Tns}) ->
    Tns.


get_imports(#'wsdl:definitions'{import = undefined}) ->
    [];
get_imports(#'wsdl:definitions'{import = Imports}) ->
    [Location || #'wsdl:import'{location = Location} <- Imports].

get_operations(#'wsdl:definitions'{service = Services} = Wsdl, 
               #interface{service = Service, port = Port} = Interface) ->
    case lists:keyfind(Service, #'wsdl:service'.name, Services) of
        false ->
            Interface;
        #'wsdl:service'{port = Ports} ->
            case lists:keyfind(Port, #'wsdl:wsdl_port'.name, Ports) of
                false ->
                    Interface;
                #'wsdl:wsdl_port'{binding = Binding, choice = Extensions} ->
                    Binding_str = erlsom_lib:localName(Binding),
                    Interface2 = 
                        get_ops_from_binding(Wsdl, 
                            Interface#interface{binding = Binding_str}),
                    Soap_version = Interface2#interface.version,
                    Url = get_url(Extensions, Soap_version),
                    Interface2#interface{url = Url}
            end
    end.

get_url(Extensions, '1.1') ->
    case lists:keyfind('soap:address', 1, Extensions) of
        false ->
            undefined;
        #'soap:address'{location = Url} ->
            Url
    end;
get_url(Extensions, '1.2') ->
    case lists:keyfind('soap12:tAddress', 1, Extensions) of
        false ->
            undefined;
        #'soap12:tAddress'{location = Url} ->
            Url
    end.

get_ops_from_binding(#'wsdl:definitions'{binding = Bindings} = Wsdl, 
                     #interface{binding = Binding} = Interface) ->
    case lists:keyfind(Binding, #'wsdl:binding'.name, Bindings) of
        false ->
            Interface;
        #'wsdl:binding'{type = Port_type, choice = Extension_elements, 
                        operation = Operations} ->
            Interface2 = add_soap_info(Extension_elements, Interface), 
            Port_type_str = erlsom_lib:localName(Port_type),
            Interface3 = 
                get_ops_from_port_type(Wsdl, 
                    Interface2#interface{port_type = Port_type_str}),
            get_ops_from_binding2(Operations, Interface3)
    end.

add_soap_info(Extension_els, Interface) ->
    case lists:keyfind('soap:binding', 1, Extension_els) of
        false ->
            case lists:keyfind('soap12:tBinding', 1, Extension_els) of
                false ->
                    throw({error, "no SOAP 1.1 or SOAP 1.2 binding found"});
                #'soap12:tBinding'{style = Style}  ->
                    Interface#interface{version = '1.2',
                                        style = Style,
                                        soap_ns = ?SOAP12_NS}
            end;
        #'soap:binding'{style = Style} ->
            Interface#interface{version = '1.1',
                                style = Style,
                                soap_ns = ?SOAP_NS}
    end.

%% Need to get the soapAction for each operation from the binding.
%% Note that an empty (but quoted) value must be used if no value
%% is specified by the binding (Basic Profile 1.1, R1109).
get_ops_from_binding2(Operations, #interface{ops = Ops} = Interface) ->
    Ops2 = [get_op_from_binding(Op, Operations) || Op <- Ops],
    Interface#interface{ops = Ops2}.

get_op_from_binding(#op{name = Name} = Op, Operations) ->
    case lists:keyfind(Name, #'wsdl:bindingOperation'.name, Operations) of
        false ->
            Op;
        #'wsdl:bindingOperation'{choice = Extensions,
                                 input = Input} ->
            Action = get_action(Extensions),
            Ns = get_input_ns(Input),
            Op#op{soap_action = Action, wrapper_ns = Ns}
    end.

get_action(Extensions) ->
    case lists:keyfind('soap:operation', 1, Extensions) of
        false ->
            "";
        #'soap:operation'{soapAction = undefined} ->
            "";
        #'soap:operation'{soapAction = Action} ->
            Action
    end.

get_input_ns(undefined) ->
    undefined;
get_input_ns(#'wsdl:bindingOperationMessage'{choice = Extensions}) ->
    case lists:keyfind('soap:body', 1, Extensions) of
        false ->
            undefined;
        #'soap:body'{namespace = Namespace, use = Use} ->
            case string:to_lower(Use) of
                "encoded" ->
                    throw({error, "use of \"encoded\" messages is not supported"});
                _ ->
                    ok
            end,
            Namespace
    end.

get_ops_from_port_type(#'wsdl:definitions'{portType = Port_types} = Wsdl, 
                       #interface{port_type = Port_type, ops = Ops} = Interface) ->
    case lists:keyfind(Port_type, #'wsdl:portType'.name, Port_types) of
        false ->
            Interface;
        #'wsdl:portType'{operation = Operations} ->
            case process_ops(Wsdl, Operations, Interface) of
                [] ->
                    {error, "No request-response or one-way operations found"};
                Result  ->
                    Interface#interface{ops = Ops ++ Result}
            end
    end.

process_ops(Wsdl, Operations, Interface) ->
    Filter = 
        fun(#'wsdl:operation'{choice1 = Type}) ->
            case Type of 
                #'wsdl:request-response-or-one-way-operation'{} ->
                    true;
                _ ->
                    false
            end
        end,
    [process_op(Wsdl, Op, Interface) || Op <- Operations, Filter(Op)].

process_op(Wsdl, #'wsdl:operation'{name = Name, choice1 = Type},
           #interface{model = Model}) ->
    #'wsdl:request-response-or-one-way-operation'{input = In_param, 
                                                  output = Out_param} = Type,
    #'wsdl:param'{message = In_message} = In_param,
    In = erlsom_lib:localName(In_message),
    In_type = type_for_message(Wsdl, In, Model),
    case Out_param of
        undefined ->
            Op_type = notification,
            Out_type = undefined;
        _ ->
            Op_type = request_response,
            #'wsdl:param'{message = Out_message} = Out_param,
            Out = erlsom_lib:localName(Out_message),
            Out_type = type_for_message(Wsdl, Out, Model)
    end,
    #op{name = Name, op_type = Op_type, 
        operation = list_to_atom(Name),
        in_type = In_type, 
        out_type = Out_type}.

type_for_message(#'wsdl:definitions'{message = Messages}, Message, Model) ->
    case lists:keyfind(Message, #'wsdl:message'.name, Messages) of
        false ->
            {error, "Message " ++ Message ++ " not found"};
        #'wsdl:message'{part = undefined} ->
            [];
        #'wsdl:message'{part = Parts} ->
            [type_for_part(P, Model) || P <- Parts]
    end.

type_for_part(#'wsdl:part'{element = undefined, 
                           type = Type,
                           name = Name}, Model) ->
    {Name, type_for_type(Type, Model)};
type_for_part(#'wsdl:part'{element = Element,
                           name = Name}, Model) ->
    %% what we need is the type
    LocalPart = erlsom_lib:localName(Element),
    Uri = erlsom_lib:getUriFromQname(Element),
    Prefix = erlsom_lib:getPrefixFromModel(Model, Uri),
    Element_name = make_name(Prefix, LocalPart),
    {Name, type_for_element(list_to_atom(Element_name), Model)}.

type_for_element(Element, Model) ->
    erlsom_lib:getTypeFromElement(Element, Model).

type_for_type(Type, Model) ->
    Uri = erlsom_lib:getUriFromQname(Type),
    case Uri of 
        "http://www.w3.org/2001/XMLSchema" ->
            schema_type(Type);
        _ ->
            LocalPart = erlsom_lib:localName(Type),
            Prefix = erlsom_lib:getPrefixFromModel(Model, Uri),
            make_name(Prefix, LocalPart)
    end.

%% TODO: use proper accessor functions
%% -record(qname, {uri, localPart, prefix, mappedPrefix}).
schema_type({qname, _, Localpart, _, _}) ->
    "s:" ++ Localpart;
schema_type(_) ->
    "s:string".

make_name(Prefix, LocalPart) ->
    case Prefix of 
        undefined ->
            LocalPart; 
        "" ->
            LocalPart; 
        _ ->
            Prefix ++ ":" ++ LocalPart
    end.

%% While parsing the WSDL it was necessary to consider also the option 
%% that this might be an "rpc" type of wsdl, and therefore a message 
%% could have more than one part. No we know that this is not the 
%% case, change the list of parts (which must have 1 element) to just 
%% that one element (no longer a list).
%%
%% For "rpc" style WSDLs, the new wrapped type must be linked to the
%% operations.
clean_up(#interface{ops = Ops, 
                    style = Style,
                    target_ns = Tns,
                    tns_prefix = TnsPrefix} = Interface) ->
    Interface#interface{ops = [clean_up(Op, Style, Tns, TnsPrefix) || Op <- Ops]}.

clean_up(#op{name = Name, 
             wrapper_ns = Ns,
             out_type = Out_type} = Op, "rpc", Tns, TnsPrefix) ->
    Prefix = case Ns of
                 Tns when is_list(TnsPrefix)  -> 
                     TnsPrefix ++ ":";
                 _ ->
                     ""
             end,
    OutName = case Out_type of
                  undefined ->
                      undefined;
                  _ -> 
                      list_to_atom(Prefix ++ Name ++ "Response")
              end,
    Op#op{in_type = list_to_atom(Prefix ++ Name), 
          out_type = OutName};
clean_up(#op{in_type = [{_N1, In}], out_type = [{_N2, Out}]} = Op, _, _, _) ->
    Op#op{in_type = In, out_type = Out};
clean_up(#op{in_type = [{_Name, In}], out_type = undefined} = Op, _, _, _) ->
    Op#op{in_type = In};
clean_up(#op{name = Name}, _, _, _) ->
    throw({error, "Operation " ++ Name ++ " uses messages with more than 1 part, "
          "which is not supported for document style operations"}).

%% If the binding of the specified port has style = "rpc", the WSDL 
%% specifies which parameters must be used for each operation. 
%%
%% These parameters must be wrapped in an XML element that has the name of the 
%% operation. 
%%
%% Both the operation and the name of the parameters are not in the "types" 
%% part of the WSDL, and therefore also not in the "model" of the $interface{}.
%%
%% See https://msdn.microsoft.com/en-us/library/ms996466.aspx for a nice 
%% description.
%%
%% For each RPC/literal operation
%% 1. For each part in the input and output messages of that operation, declare 
%%    a type with the contents described in step 2.
%% 2. Declare an element with the name of the part, the type referenced by 
%%    type=". The element form must be unqualified.
%% 3. Declare a global element with the operation name and the namespace from 
%%    soap:body/@namespace in the binding. Make the type of this element the 
%%    one defined in step 1 for the input message.
%% 4. Declare a global element with the operation name and the word Response 
%%    appended to it and the namespace from soap:body/@namespace in the binding. 
%%    Make the type of this element the one defined in step 1 for the output 
%%    message.
%% 5. Change the input message to contain one part and reference the element 
%%    you declared in step 3.
%% 6. Change the output message to contain one part and reference the element 
%%    you declared in step 4.
%% 7. Change the style to document in the binding.
wrap_rpc_types(#interface{ops = Ops,
                          target_ns = Tns,
                          model = Model,
                          imported = Namespaces} = Interface,
              Options) ->
    OtherNamespaces = proplists:get_value(namespaces, Options, []),
    AllNamespaces = Namespaces ++ OtherNamespaces,
    ErlsomOptions = proplists:get_value(erlsom_options, Options, []),
    %% Since every operation kan have its own namespace, 
    %% there is an xsd for each of them.
    %%
    %% There is a special case if the namespace of the 
    %% operation == one of the already declared namespaces, 
    %% because each namespace can only have one prefix.
    %% If the namespace of the operation == tns, then 
    %% this has an effect on the types of the messages
    Xsds = [xsd_from_op(Op, AllNamespaces) || Op <- Ops],
    {CombinedModels, _, _} = lists:foldl(fun add_model/2, {Model, 
                                                        AllNamespaces,
                                                        ErlsomOptions}, Xsds),
    TnsPrefix = proplists:get_value(Tns, AllNamespaces, undefined),
    Interface#interface{model = CombinedModels,
                        tns_prefix = TnsPrefix}.

add_model({Xsd, Ns}, {CombinedModel, Namespaces, ErlsomOptions}) ->
    Prefix = proplists:get_value(Ns, Namespaces, undefined),
    {ok, Model} = erlsom:compile_xsd(Xsd, 
                                     [{include_any_attribs, false}
                                     ,{already_imported, Namespaces}
                                     ,{namespaces, [{Ns, Prefix}]} 
                                     | ErlsomOptions]),
    NewModel = case CombinedModel of
                   undefined ->
                       Model;
                   _ ->
                       erlsom:add_model(Model, CombinedModel)
               end,
    {NewModel, Namespaces, ErlsomOptions}.

xsd_from_op(#op{name = Name, 
                wrapper_ns = Namespace,
                in_type = InParts, 
                out_type = OutParts}, Namespaces) ->
    Elements = [in_rpc_element(Name, InParts),
                out_rpc_element(Name, OutParts)],
    Namespace_decls = [namespace_decl(N) || N <- Namespaces],
    {lists:flatten(
         ["<s:schema xmlns:s=\"http://www.w3.org/2001/XMLSchema\"\n",
          Namespace_decls,
          "          xmlns:tns=\"", Namespace, "\"\n",
          "          elementFormDefault=\"qualified\"\n",
          "          targetNamespace=\"", Namespace, "\">\n",
          Elements,
          "</s:schema>\n"]),
      Namespace}.

in_rpc_element(Name, InParts) ->
    ["  <s:element name=\"", Name, "\">\n",
     "    <s:complexType>\n",
     "       <s:sequence>\n",
     [rpc_part(P) || P <- InParts],
     "      </s:sequence>\n",
     "    </s:complexType>\n",
     "  </s:element>\n"].

out_rpc_element(Name, OutParts) ->
    in_rpc_element(Name ++ "Response", OutParts).

rpc_part({Name, Type}) ->
    ["      <s:element name=\"", Name, "\"",
                 %%  " form=\"unqualified\"",
                     " type=\"", Type, "\">\n",
     "      </s:element>\n"].

namespace_decl({_Uri, undefined}) ->
    [];
namespace_decl({Uri, Prefix}) ->
    ["          xmlns:", Prefix, "=\"", Uri, "\"\n"].




%% ---------------------------------------------------------------------------
%% Get a file from an URL spec.
%% ---------------------------------------------------------------------------
get_url_file("http://"++_ = URL) ->
    case httpc:request(URL) of
        {ok,{{_HTTP,200,_OK}, _Headers, Body}} ->
            {ok, Body};
        {ok,{{_HTTP, _RC, _Emsg}, _Headers, _Body}} ->
            {error, "failed to retrieve: "++URL};
        {error, _Reason} ->
            {error, "failed to retrieve: "++URL}
        end;
get_url_file("file://" ++ F_name) ->
    case file:read_file(F_name) of
        {ok, Bin} ->
            {ok, Bin};
        _ ->
         {error, "failed to read: " ++ F_name}
    end;
get_url_file(F_name) ->
    get_url_file("file://" ++ F_name).
