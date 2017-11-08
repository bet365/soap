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

-module(soap_SUITE).
-include_lib("common_test/include/ct.hrl").
-include("test_service.hrl").
-compile(export_all).

-define(HOST, "http://localhost").
-define(PORT, 8080).
-define(URL, ?HOST ++ ":" ++ integer_to_list(?PORT)).

%%--------------------------------------------------------------------
%% How to use this file?
%%
%% > ct:run_test([{spec, "test_specs.spec"}]).
%%
%% Note: rebar will use "test.config", which points to cowboy 
%% version 1. In order to test cowboy v.1 using rebar, change the 
%% config file..
%%
%% To test with cowboy_2:
%% (make sure that the path for cowboy points to the right directory)
%% > ct:run_test([{spec, "test_specs.spec"}, {config, "e:/e_soap/soap/test/cowboy_2.cfg"}]).
%%
%% To set cowboy to v.2:
%% code:add_pathsa(["e:/e_soap/soap/deps/cowboy_2/cowboy/ebin",
%%                  "e:/e_soap/soap/deps/cowboy_2/cowboy/deps/cowlib/ebin",
%%                  "e:/e_soap/soap/deps/cowboy_2/cowboy/deps/ranch/ebin"]).
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% Test server callback functions
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% Function: suite() -> DefaultData
%% DefaultData: [tuple()]  
%% Description: Require variables and set default values for the suite
%%--------------------------------------------------------------------
suite() -> 
  [{timetrap,{minutes,1}}].

%%--------------------------------------------------------------------
%% Function: init_per_suite(Config) -> Config
%% Config: [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Description: Initiation for the whole suite
%%
%% Note: This function is free to add any key/value pairs to the Config
%% variable, but should NOT alter/remove any existing entries.
%%--------------------------------------------------------------------
init_per_suite(Config) ->
  ibrowse:start(),
  Config.

%%--------------------------------------------------------------------
%% Function: end_per_suite(Config) -> _
%% Config: [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Description: Cleanup after the whole suite
%%--------------------------------------------------------------------
end_per_suite(_Config) ->
  ibrowse:stop(),
  ok.

%%--------------------------------------------------------------------
%% Function: groups() -> [Group]
%%
%% Group = {GroupName,Properties,GroupsAndTestCases}
%% GroupName = atom()
%%   The name of the group.
%% Properties = [parallel | sequence | Shuffle | {RepeatType,N}]
%%   Group properties that may be combined.
%% GroupsAndTestCases = [Group | {group,GroupName} | TestCase]
%% TestCase = atom()
%%   The name of a test case.
%% Shuffle = shuffle | {shuffle,Seed}
%%   To get cases executed in random order.
%% Seed = {integer(),integer(),integer()}
%% RepeatType = repeat | repeat_until_all_ok | repeat_until_all_fail |
%%              repeat_until_any_ok | repeat_until_any_fail
%%   To get execution of cases repeated.
%% N = integer() | forever
%%
%% Description: Returns a list of test case group definitions.
%%--------------------------------------------------------------------
groups() ->
  [{cowboy_server, [sequence],
      [correct_sms
      ,sms_fault
      ,sms_invalid_xml
      ,sms_wrong_method
      ,sms_handler_crash
      ,{soap_11_client, [sequence], [client_11_ok ,client_11_fault]}
      ,{soap_12_client, [sequence], [client_12_ok ,client_12_fault]}
      ]}
  ,{mochi_server, [sequence],
      [correct_sms
      ,sms_fault
      ,sms_invalid_xml
      ,sms_wrong_method
      ]}
  ,{inets_server, [sequence],
      [correct_sms
      ,sms_fault
      ,sms_invalid_xml
      ,sms_wrong_method
      ]}
  ,{tempconvert, [],
      [tempconvert_w3schools
      ,{tempconvert_local, [], [tempconvert_local_ok]}
      ,test_client
      ]}
  ,{strict, [],
      [strict
      ]}
  ,{tempconvert_12, [],
      [tempconvert_w3schools %% same as for v. 1.1
      ,tempconvert_fault %% the server only returns a fault with v 1.2
      ]}
  ,{client, [],
      [client_no_error
      ,client_unicode
      ,client_unicode_binary
      ,client_fault_exception
      ,client_http_error
      ,client_wrong_request_header
      ,client_wrong_response_header
      ,client_invalid_message
      ,client_malformed_message
      ,client_fault_encoding_header
      ,client_encoded_header
      ,client_two_headers
      ,client_one_header_one_skipped
      ,ibrowse_client_timeout
      ,raw 
      ,raw_client
      ,raw_client_error
      ,{inets_client, [], [inets_client_no_error
                          ,inets_client_unicode
                          ,inets_client_timeout]}
      ,{faults_1_1, [], [client_client_fault
                        ,client_server_fault
                        ,fault_w_special_code
                        ,fault_w_actor
                        ,fault_w_details]}
      ,{faults_1_2, [], [fault_1_2_simple
                        ,fault_1_2_subcode
                        ,fault_1_2_actor
                        ]}
      ]}
  ,{wsdl_2_0, [],
      [wsdl_2_0_example
      ]}
  ,{soap_req, [],
      [soap_req_no_headers
      ,soap_req_w_headers
      ]}
  ,{attachments, [],
      [attachments_echo]}
  ,{erlang2wsdl, [],
      [erlang2wsdl_store
      ]}
  ,{wsdl2erlang, [],
      [reiseauskunft
      ]}
  ,{wsdls, [],
      [wsdls_clickatell
      ,wsdls_salesforce
      ,wsdls_europepmc
      ,wsdls_ebay
      ,wsdls_rpc
      ,wsdls_rpc_2
      ,wsdls_issue_4_literal
      ]}
  ].

init_per_group(cowboy_server, Config) ->
  {ok, _} = soap:start_server(sendService_test_server, 
               [{"[a-zA-Z]+", invalid}, 
                {"^\\+?[0-9]{4,12}$", valid},
                {"[0-9]{13,}", throw},
                {http_server, cowboy_version()}]),
  Config;
init_per_group(inets_server, Config) ->
  {ok, _} = soap:start_server(sendService_test_server, 
               [{http_server, soap_server_inets},
                {"[a-zA-Z]+", invalid}, 
                {"^\\+?[0-9]{4,12}$", valid},
                {"[0-9]{13,}", throw}]),
  Config;
init_per_group(mochi_server, Config) ->
  {ok, _} = soap:start_server(sendService_test_server, 
                [{http_server, soap_server_mochiweb},
                {"[a-zA-Z]+", invalid}, 
                {"^\\+?[0-9]{4,12}$", valid},
                {"[0-9]{13,}", throw}]),
  Config;
init_per_group(soap_11_client, Config) ->
  Options = [{http_client, ibrowse}, 
             {namespaces, [{"com.esendex.ems.soapinterface", "P0"}]},
             {generate, client}, {client_name, "sendService_client"},
             {generate_tests, none},
             {port, "SendServiceSoap"}, {service, "SendService"}],
  compile_wsdl("SendService.wsdl", Options, Config),
  Config;
init_per_group(soap_12_client, Config) ->
  Options = [{http_client, ibrowse}, 
             {namespaces, [{"com.esendex.ems.soapinterface", "P0"}]},
             {generate, client}, {client_name, "sendService_client"},
             {generate_tests, none},
             {port, "SendServiceSoap12"}, {service, "SendService"}],
  compile_wsdl("SendService.wsdl", Options, Config),
  Config;
init_per_group(tempconvert, Config) ->
  Options = [{http_client, ibrowse}, {http_server, cowboy_version()},
             {namespaces, [{"http://www.w3schools.com/xml/", "t"}]},
             {generate, both}, {generate_tests, none},
             {client_name, "tempconvert_client"},
             {server_name, "tempconvert_server"},
             {service, "TempConvert"}, {port, "TempConvertSoap"}
            ],
  compile_wsdl("tempconvert.wsdl", Options, Config),
  Config;
init_per_group(strict, Config) ->
  Options = [{http_client, ibrowse}, {http_server, cowboy_version()},
             {namespaces, [{"http://www.w3schools.com/xml/", "t"}]},
             {generate, both}, {generate_tests, none},
             {client_name, "tempconvert_client_strict"},
             {server_name, "tempconvert_server_strict"},
             {erlsom_options, [{strict, true}]},
             {test_values,true}, 
             {service, "TempConvert"}, {port, "TempConvertSoap"}
            ],
  compile_wsdl("tempconvert_float.wsdl", Options, Config),
  {ok, _} = soap:start_server(tempconvert_server_strict, [{port, 8080},
                                                   {http_server, cowboy_version()}]),
  Config;
init_per_group(tempconvert_12, Config) ->
  inets:start(),
  Options = [{http_client, inets},  %% use inets for a change
             {namespaces, [{"http://www.w3schools.com/xml/", "t"}]},
             {generate, client}, {generate_tests, none},
             {client_name, "tempconvert_client"},
             {service, "TempConvert"}, {port, "TempConvertSoap12"}
            ],
  compile_wsdl("tempconvert.wsdl", Options, Config),
  Config;
init_per_group(erlang2wsdl, Config) ->
  inets:start(),
  Config;
init_per_group(tempconvert_local, Config) ->
  {ok, _} = soap:start_server(tempconvert_server, [{port, 8080},
                                                   {http_server, cowboy_version()}]),
  Config;
init_per_group(client, Config) ->
  {ok, _} = soap:start_server(test_service_server, [{http_server, cowboy_version()}]),
  Config;
init_per_group(inets_client, Config) ->
  inets:start(),
  Options = [{http_client, inets}, {namespaces,[{"test",undefined}]},
             {generate, client}, {generate_tests, none},
             {client_name, "test_inets_client"},
             {service, "test_service"}, {port, "test_port"}
            ],
  compile_wsdl("test_service.wsdl", Options, Config),
  Config;
init_per_group(soap_req, Config) ->
  {ok, _} = soap:start_server(test_service_server_2, [{http_server, cowboy_version()}]),
  Config;
init_per_group(wsdl_2_0, Config) ->
  Data_dir = ?config(data_dir, Config),
  Options = [{http_client, ibrowse}, {http_server, cowboy_version()},
             {namespaces, [{"http://www.bookstore.org/booklist/xsd", undefined}]},
             {generate, both}, {generate_tests, none},
             {wsdl_version, '2.0'}, {test_values, true}, 
             {include_path, Data_dir},
             {client_name, "wsdl_2_0_client"},
             {server_name, "wsdl_2_0_server"},
             {service, "BookList"}, {port, "BookListHTTPEndpoint"}
            ],
  compile_wsdl("wsdl_2_0_example.wsdl", Options, Config),
  {ok, _} = soap:start_server(wsdl_2_0_server, [{port, 8080},
                                                {http_server, cowboy_version()}]),
  Config;
init_per_group(attachments, Config) ->
  {ok, _} = soap:start_server(europepmc_server, [{http_server, cowboy_version()}]),
  Config;
init_per_group(_, Config) ->
  Config.

end_per_group(mochi_server, _Config) ->
  ok = soap:stop_server(sendService_test_server, [{http_server, soap_server_mochiweb}]);
end_per_group(inets_server, _Config) ->
  soap:stop_server(sendService_test_server, [{http_server, soap_server_inets}]),
  ok;
end_per_group(cowboy_server, _Config) ->
  soap:stop_server(sendService_test_server),
  ok;
end_per_group(tempconvert_local, _Config) ->
  soap:stop_server(tempconvert_server),
  ok;
end_per_group(strict, _Config) ->
  soap:stop_server(tempconvert_server_strict),
  ok;
end_per_group(wsdl_2_0, _Config) ->
  soap:stop_server(wsdl_2_0_server),
  ok;
end_per_group(client, _Config) ->
  soap:stop_server(test_service_server),
  ok;
end_per_group(soap_req, _Config) ->
  soap:stop_server(test_service_server_2),
  ok;
end_per_group(attachments, _Config) ->
  soap:stop_server(europepmc_server),
  ok;
end_per_group(_, _Config) ->
  ok.

%%--------------------------------------------------------------------
%% Function: all() -> TestCases
%% TestCases: [Case] 
%% Case: atom()
%%   Name of a test case.
%% Description: Returns a list of all test cases in this test suite
%%--------------------------------------------------------------------      
all() -> 
  [{group, cowboy_server},
  {group, inets_server},
  {group, tempconvert},
  {group, tempconvert_12},
  {group, strict},
  {group, client},
  {group, soap_req},
  {group, wsdls}, %% takes a long time
  {group, erlang2wsdl},
  {group, wsdl2erlang},
  {group, attachments},
  {group, wsdl_2_0},
  %% for some reason the mochi server 
  %% seems to continue answering requests after shutdown
  %% for a while, therefore put it last.
  {group, mochi_server},
  issue_4_encoded
  ].

%%-------------------------------------------------------------------------
%% Test cases start here.
%%-------------------------------------------------------------------------

correct_sms() ->
  [{userdata,[{doc,"handle a correct request"}]}].
correct_sms(_Config) ->
  Message = correct_message(),
  Headers = [{"Content-Type", correct_content_type()} | correct_headers()],
  Method = correct_method(),
  {ok, "200", _, _} = ibrowse:send_req(?URL, Headers, Method, Message, []).

sms_fault() ->
  [{userdata,[{doc,"trigger a client error"}]}].
sms_fault(_Config) ->
  Message = client_error_message(),
  Headers = [{"Content-Type", correct_content_type()} | correct_headers()],
  Method = correct_method(),
  {ok, "500", _, _} = ibrowse:send_req(?URL, Headers, Method, Message, []).

sms_invalid_xml() ->
  [{userdata,[{doc,"Malformed XML"}]}].
sms_invalid_xml(_Config) ->
  Message = invalid_xml_message(),
  Headers = [{"Content-Type", correct_content_type()} | correct_headers()],
  Method = correct_method(),
  {ok, "500", _, _} = ibrowse:send_req(?URL, Headers, Method, Message, []).

sms_wrong_method() ->
  [{userdata,[{doc,"R1114 An INSTANCE SHOULD use a \"405 Bad Request\" HTTP status code if a HTTP request message's method is not \"POST\""}]}].
sms_wrong_method(_Config) ->
  Message = correct_message(),
  Headers = [{"Content-Type", correct_content_type()} | correct_headers()],
  Method = delete,
  {ok, "405", _, _} = ibrowse:send_req(?URL, Headers, Method, Message, []).

sms_handler_crash() ->
  [{userdata,[{doc,"If the handler crashes this must result in a fault"}]}].
sms_handler_crash(_Config) ->
  Message = unexpected_xml_message(),
  Headers = [{"Content-Type", correct_content_type()} | correct_headers()],
  Method = correct_method(),
  {ok, "500", _, _} = ibrowse:send_req(?URL, Headers, Method, Message, []).

client_11_ok() ->
  [{userdata,[{doc,"use the generated client, receive OK answer"}]}].
client_11_ok(_Config) ->
  %% Normally one should include the record definition and use
  %% record syntax.
  %% TODO: the P0 prefixes should not be necessary.
  {ok, 200, _,  _, {'P0:sendMessageResponse', "OK"}, [], _} =
    sendService_client:'SendMessage'({'P0:sendMessage', "+31234567890", 
                            "Hello there", "Text"}, [], []).

client_11_fault() ->
  [{userdata,[{doc,"use the generated client, receive fault answer"}]}].
client_11_fault(_Config) ->
  {fault, 500, _,  _, 
   #soap_fault_1_1{
     faultcode = #faultcode{uri = "http://schemas.xmlsoap.org/soap/envelope/", 
                            code = "Server"},
     faultstring = "exception" ++ _, 
     faultactor = undefined,
     detail = []}, 
   [], _} =
    sendService_client:'SendMessage'({'P0:sendMessage', "01234567890123456789", 
                            "Hello there", "Text"}, [], []).

client_12_ok() ->
  [{userdata,[{doc,"use the generated client, receive OK answer"}]}].
client_12_ok(_Config) ->
  {ok, 200, Http_headers,  _, {'P0:sendMessageResponse', "OK"}, [], Raw} =
    sendService_client:'SendMessage'({'P0:sendMessage', "+31234567890", 
                            "Hello there", "Text"}, [], []),
  "application/soap+xml" = proplists:get_value("Content-Type", Http_headers),
  {_, 2} = binary:match(Raw, <<"OK">>).

client_12_fault() ->
  [{userdata,[{doc,"use the generated client, receive fault answer"}]}].
client_12_fault(_Config) ->
  {fault, 500, _,  _, 
   #soap_fault_1_2{
     code = #faultcode{uri = "http://www.w3.org/2003/05/soap-envelope", 
                       code = "Receiver"},
     reason = [#faultreason{text = "exception" ++ _, language = "en"}],
     detail = []}, 
   [], _} =
    sendService_client:'SendMessage'({'P0:sendMessage', "01234567890123456789", 
                            "Hello there", "Text"}, [], []).

tempconvert_w3schools(_Config) ->
  {ok,200, _, [], _, [], _} = 
    tempconvert_client:'CelsiusToFahrenheit'(
                         {'t:CelsiusToFahrenheit', "37.8"}, [], []).

tempconvert_fault(_Config) ->
  {fault,500, _, [], _, [], _} = 
    tempconvert_client:'CelsiusToFahrenheit'(<<"this won't work">> , [], []).

tempconvert_local_ok(_Config) ->
  {ok,200, _, [], _, [], _} = 
    tempconvert_client:'CelsiusToFahrenheit'(
                         {'t:CelsiusToFahrenheit', "37.8"}, [], 
                         [{url, "http://localhost:8080"}]).

strict(_Config) ->
  {ok,200, _, [], {'t:CelsiusToFahrenheitResponse',3.14159}, [], _} = 
    tempconvert_client_strict:'CelsiusToFahrenheit'(
                         {'t:CelsiusToFahrenheit', 37.8}, [], 
                         [{url, "http://localhost:8080"}]).

wsdl_2_0_example(_Config) ->
  {ok,200, _, [], _, [], _} = 
  wsdl_2_0_client:getBookList(
    {getBookListType, ["Armstrong", "Hebert"], undefined, undefined, undefined, undefined}, 
    [], [{url, "http://localhost:8080"}]).

test_client(_Config) ->
  {ok, _} = soap:make_test_client(tempconvert_client).


client_no_error(_Config) ->
  {ok,200, Http_headers, [],#response_body{response = "ok"}, [], _} = 
    test_service_client:do_test(#request_body{expected_response="ok"}, [], []),
  "text/xml" = proplists:get_value("Content-Type", Http_headers).

client_unicode(_Config) ->
  {ok,200, _, [],#response_body{response = "بِسْمِ ٱلرَّحْمـَبنِ ٱلرَّحِيمِ"}, [], _} = 
    test_service_client:do_test(#request_body{expected_response=
                                              "بِسْمِ ٱلرَّحْمـَبنِ ٱلرَّحِيمِ"}, [], []).

client_unicode_binary(_Config) ->
  {ok,200, _, [],#response_body{response = "بِسْمِ ٱلرَّحْمـَبنِ ٱلرَّحِيمِ"}, [], _} = 
    test_service_client:do_test(#request_body{
                                   expected_response=
                                       unicode:characters_to_binary("بِسْمِ ٱلرَّحْمـَبنِ ٱلرَّحِيمِ")},
                                [], []).

inets_client_no_error(_Config) ->
  {ok,200, _, [],#response_body{}, [], _} = 
  test_inets_client:do_test(#request_body{expected_response="sleep:0"}, [], []).

inets_client_unicode(_Config) ->
  {ok,200, _, [],#response_body{response = "بِسْمِ ٱلرَّحْمـَبنِ ٱلرَّحِيمِ"}, [], _} = 
    test_inets_client:do_test(#request_body{expected_response=
                                              "بِسْمِ ٱلرَّحْمـَبنِ ٱلرَّحِيمِ"}, [], []).

inets_client_timeout(_Config) ->
  {error,{client,{http_request,timeout}}, _} = 
  test_inets_client:do_test(#request_body{expected_response="sleep:2"}, [], 
                            [{http_options, [{timeout, 1000}]}]).

client_fault_exception(_Config) ->
  {fault,500, _, [],
   #soap_fault_1_1{
     faultcode = #faultcode{uri = "http://schemas.xmlsoap.org/soap/envelope/", 
                            code = "Server"},
     faultactor = undefined,
     faultstring = "exception" ++ _}, [], _} = 
    test_service_client:do_test(#request_body{expected_response="not_ok"}, [], []).

client_client_fault(_Config) ->
  %% technically the message is correct, therefore it is still a server error
  {fault,500, _, [],
   #soap_fault_1_1{
     faultcode = #faultcode{uri = "http://schemas.xmlsoap.org/soap/envelope/", 
                            code = "Server"},
     faultactor = undefined,
     faultstring = "exception" ++ _}, [], _} = 
    test_service_client:do_test(#request_body{expected_response="not_ok"}, [], []).

client_server_fault(_Config) ->
  {fault,500, _, [],
   #soap_fault_1_1{
     faultcode = #faultcode{uri = "http://schemas.xmlsoap.org/soap/envelope/", 
                            code = "Server"},
     faultactor = undefined,
     faultstring = "exception" ++ _}, [], _} = 
    test_service_client:do_test(#request_body{expected_response="not_ok"}, [], []).

client_http_error(_Config) ->
  {error,{server,405,  _}, _} = 
    test_service_client:do_test(#request_body{expected_response="405"}, [], []).

client_wrong_request_header(_Config) ->
  %% This is considered to be a "Client"-error.
  {fault,500, _, [],
   #soap_fault_1_1{
     faultcode = #faultcode{uri = "http://schemas.xmlsoap.org/soap/envelope/", 
                            code = "Client"},
     faultactor = undefined,
     faultstring = "exception" ++ _}, [], _} = 
    test_service_client:do_test(#request_body{expected_response="ok"}, ["<not xml>"], []).

client_wrong_response_header(_Config) ->
  {error,{client,{parsing_message,200, _, throw,
                     {error,"Malformed: Illegal character in attribute name"}}}, _} =
    test_service_client:do_test(#request_body{expected_response="wrong_header"}, [], []).

client_invalid_message(_Config) ->
  {error,{client,{parsing_message,200, _, throw,
                                {error,[{exception,{error,"unknown tag: xml"}},
                                        {stack,[undefined]},
                                        {received,{startElement,[],"xml",[],[]}}]}}}, _} =
    test_service_client:do_test(#request_body{expected_response="invalid_message"}, [], []).
    
client_malformed_message(_Config) ->
  {error,{client,{parsing_message,200, _, throw,
                      {error,"Malformed: Illegal character in literal value"}}}, _} =
    test_service_client:do_test(#request_body{expected_response="malformed_message"}, [], []).

client_fault_encoding_header(_Config) ->
  {fault,500, _, [],
   #soap_fault_1_1{
     faultcode = #faultcode{uri = "http://schemas.xmlsoap.org/soap/envelope/", 
                            code = "Server"},
     faultactor = undefined,
     faultstring = "exception" ++ _}, [], _} = 
    test_service_client:do_test(#request_body{expected_response="fault_encoding_header"}, [], []).

client_encoded_header(_Config) ->
  {ok,200, _, [#header{header_field = "hello"}], #response_body{response = "ok"}, [], _} =
    test_service_client:do_test(#request_body{expected_response="encoded_header"}, [], []).

client_two_headers(_Config) ->
  {ok,200, _, [_Hash,#header{header_field = "hello"}], #response_body{response = "ok"}, [], _} =
    test_service_client:do_test(#request_body{expected_response="two_headers"}, [], []).

client_one_header_one_skipped(_Config) ->
  {ok,200, _, [#header{header_field = "hello"}], #response_body{response = "ok"}, [], _} =
    test_service_client:do_test(#request_body{expected_response="one_header_one_skipped"}, [], []).

ibrowse_client_timeout(_Config) ->
  {error,{client,{http_request,req_timedout}}, _} = 
  test_service_client:do_test(#request_body{expected_response="sleep:2"}, [], 
                            [{http_options, [{timeout, 1000}]}]).

raw(_Config) ->
  {ok,200, _, [], #response_body{response = "raw"}, [], _} =
    test_service_client:do_test(#request_body{expected_response="raw"}, [], []).

raw_client(_Config) ->
  Message =  [<<"<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/so">>,
              <<"ap/envelope/\"><s:Body><erlsom:request_body xmlns:erl">>,
              <<"som=\"test\"><expected_response>raw</expected_response>">>,
              "</erlsom:request_body></s:Body></s:Envelope>"],
  {ok,200, _, [], #response_body{response = "raw"}, [], _} =
    test_service_client:do_test(Message, [], []).

raw_client_error(_Config) ->
  {fault,500, _, [], _, [], _} =
    test_service_client:do_test("won't work", [], []).

soap_req_no_headers(_Config) ->
  {error,{server, 401, _}, <<>>} =
    test_service_client:do_test(#request_body{expected_response="ok"}, [], []).

soap_req_w_headers(_Config) ->
  {ok,200, _, [],{response_body,"authenticated!"}, [], _} =
    test_service_client:do_test(#request_body{expected_response="ok"}, 
                                [], [{http_headers, [{"authorization", "user:pwd"}]}]).

fault_w_special_code(_Config) ->
  {fault,500, _, [],
   #soap_fault_1_1{
     faultcode = #faultcode{uri = "Name.space", 
                            code = "code"},
     faultactor = undefined,
     faultstring = "Server fault"}, [], _} = 
    test_service_client:do_test(#request_body{expected_response="fault_w_special_code"}, [], []).

fault_w_actor(_Config) ->
  {fault,500, _, [],
   #soap_fault_1_1{
     faultcode = #faultcode{uri = "http://schemas.xmlsoap.org/soap/envelope/", 
                            code = "Server"},
     faultactor = "actor",
     faultstring = "Fault with actor"}, [], _} = 
    test_service_client:do_test(#request_body{expected_response="fault_w_actor"}, [], []).

fault_w_details(_Config) ->
  {fault,500, _, [],
   #soap_fault_1_1{
     faultcode = #faultcode{uri = "Name.space", 
                            code = "code"},
     faultstring = "Fault with details",
     detail = [#faultdetail{uri = "Name.space", tag = "Tag", text = "The text"},
               #faultdetail{}]}, 
   [], _} = 
    test_service_client:do_test(#request_body{expected_response="fault_w_details"}, [], []).

fault_1_2_simple(_Config) ->
  {fault,500, _, [],
   #soap_fault_1_2{
     code = #faultcode{uri = "http://www.w3.org/2003/05/soap-envelope", 
                       code = "Receiver"},
     reason = [#faultreason{text = "SOAP 1.2 fault", language = "en"}],
     detail = []}, 
   [], _} = 
    test_service_client:do_test(#request_body{expected_response="fault_1_2_simple"}, [], 
                                [{version, '1.2'}]).

fault_1_2_subcode(_Config) ->
  {fault,500, _, [],
   #soap_fault_1_2{
     code = #faultcode{uri = "http://www.w3.org/2003/05/soap-envelope", 
                       code = "Receiver",
                       subcode = #faultcode{uri = "uri",
                                            code = "code"}},
     reason = [#faultreason{text = "SOAP 1.2 fault", language = "en"}],
     detail = []}, 
   [], _} = 
    test_service_client:do_test(#request_body{expected_response="fault_1_2_subcode"}, [], 
                                [{version, '1.2'}]).

fault_1_2_actor(_Config) ->
  {fault,500, _, [],
   #soap_fault_1_2{
     code = #faultcode{uri = "http://www.w3.org/2003/05/soap-envelope", 
                       code = "Receiver",
                       subcode = #faultcode{uri = "uri",
                                            code = "code"}},
     reason = [#faultreason{text = "SOAP 1.2 fault", language = "en"}],
     role = "actor",
     detail = [#faultdetail{uri = "Name.space", tag = "Tag", text = "The text"},
               #faultdetail{}]}, 
   [], _} = 
    test_service_client:do_test(#request_body{expected_response="fault_1_2_actor"}, [], 
                                [{version, '1.2'}]).

attachments_echo(_Config) ->
  Attachment = {[{"H1", "V1"}], <<"test attachment">>},
  {ok,200, _, [],_, [Attachment], Raw} =
    %%europepmc_client:getFulltextXML(#getFulltextXML{id="PMC3542247", source="PMC"}, 
    %% can only import 1 generated hrl, because INTERFACE can only be defined 1x
    europepmc_client:getFulltextXML({getFulltextXML, "PMC3542247", "PMC", undefined}, 
                                [],
                                [{url, "http://localhost:8080"}], 
                                [Attachment]),
    io:format("Raw: ~p~n", [Raw]),
    {_, 15} = binary:match(Raw, <<"test attachment">>).

wsdls_clickatell(Config) ->
  test_wsdl(Config, "clickatell.wsdl").

wsdls_salesforce(Config) ->
  test_wsdl(Config, "salesforce_small.wsdl").

wsdls_europepmc(Config) ->
  test_wsdl(Config, "europepmc.wsdl").

wsdls_ebay(Config) ->
  test_wsdl(Config, "ebaySvc_short.wsdl").

wsdls_rpc(Config) ->
  test_wsdl(Config, "rpc_literal.wsdl").

wsdls_rpc_2(Config) ->
  test_wsdl(Config, "rpc_literal_2.wsdl").

wsdls_issue_4_literal(Config) ->
  test_wsdl(Config, "issue_4_literal.wsdl").

reiseauskunft(Config) ->
  Ns = [{"http://www.bahn.de/webservices/dritte/ping/response","P10"},
        {"http://www.bahn.de/webservices/dritte/ping/request","P9"},
        {"http://www.bahn.de/webservices/dritte/monitoring/response","P8"},
        {"http://www.bahn.de/webservices/dritte/monitoring/request","P7"},
        {"http://www.bahn.de/webservices/dritte/datatypes/primitive","P6"},
        {"http://www.bahn.de/webservices/dritte/datatypes/db","P5"},
        {"http://www.bahn.de/webservices/dritte/datatypes/common","P4"},
        {"http://www.bahn.de/webservices/dritte/angebotssuche/response","P3"},
        {"http://www.bahn.de/webservices/dritte/angebotssuche/request","P2"},
        {"http://www.bahn.de/webservices/dritte/angebotsdetails/response","P1"},
        {"http://www.bahn.de/webservices/dritte/angebotsdetails/request","P0"},
        {"http://www.bahn.de/webservices/dritte","P"}],
  Include_fun = fun(Namespace, Url, _, _) -> 
    Pf = proplists:get_value(Namespace, Ns, "pf"),
    {ok,{{_,200,_}, _, Body}} = httpc:request(Url), 
    {Body, Pf} 
  end,
  Options = [{generate,client},
             {client_name,"client"},
             {hrl_name, "test"}, 
             {namespaces, Ns},
             {http_client,soap_client_ibrowse},
             {generate_tests, none}, {test_values,false},
             {erlsom_options, [{include_fun, Include_fun}]}],
  compile_wsdl("reiseauskunft.wsdl", Options, Config).

erlang2wsdl_store(Config) ->
  process_hrl("store.hrl", Config).

issue_4_encoded(Config) ->
  Options = [{generate,both},
             {server_name,"server"},{client_name,"client"},
             {hrl_name, "test"}, {automatic_prefixes, true},
             {http_server, cowboy_version()},
             {http_client,soap_client_ibrowse},
             {generate_tests, none},
             {test_values,true}],
  {error,"use of \"encoded\" messages is not supported"} =
  try 
    compile_wsdl("issue_4.wsdl", Options, Config)
  catch
    throw:Message ->
      Message
  end.

%%-------------------------------------------------------------------------
%% Internal functions
%%-------------------------------------------------------------------------

test_wsdl(Config, Wsdl_file) ->
  Data_dir = ?config(data_dir, Config),
  Wsdl = filename:join(Data_dir, Wsdl_file),
  test_wsdl_abs_path(Config, Wsdl).
  
test_wsdl_abs_path(Config, Wsdl) ->
  compile_wsdl_abs_path(Wsdl, [{generate,both},
                      {erlsom_options, [{include_dirs, [?config(data_dir, Config)]}]},
                      {server_name,"server"},{client_name,"client"},
                      {hrl_name, "test"}, {automatic_prefixes, true},
                      {http_server, cowboy_version()},
                      {http_client,soap_client_ibrowse},
                      {generate_tests, none},
                      {test_values,true}],
              Config),
  {ok, Operations} = 
    soap:make_test_client(client, [{soap_options, 
                                   [{url,"http://localhost:8080"}]}, 
                                   {test_module, "test_client"},
                                   {hrl_name, "test"}]),
  compile("test_client"),
  soap:start_server(server),
  [test_operation(test_client, Operation) || Operation <- Operations],
  soap:stop_server(server).

compile_wsdl(Wsdl_file, Options, Config) ->
  Data_dir = ?config(data_dir, Config),
  Wsdl = filename:join(Data_dir, Wsdl_file),
  compile_wsdl_abs_path(Wsdl, Options, Config).

compile_wsdl_abs_path(Wsdl, Options, Config) ->
  ok = soap:wsdl2erlang(Wsdl, Options),
  case proplists:get_value(server_name, Options) of
    undefined ->
      ok;
    Server_name ->
      compile(Server_name)
  end,
  case proplists:get_value(client_name, Options) of
    undefined ->
      ok;
    Client_name ->
      compile(Client_name)
  end,
  Config.

compile(Module_file) ->
  {ok, _} = compile:file(Module_file),
  Module = list_to_atom(Module_file),
  code:purge(Module),
  {module, _} = code:load_abs(Module_file).

test_operation(Module, Function) ->
  {ok, 200, _, _, _, [], _} = Module:Function().


process_hrl(Hrl_file, Config) ->
  %% create a WSDL called "service.wsdl" out of the .hrl file
  make_wsdl(Hrl_file, Config),
  test_wsdl_abs_path(Config, "service.wsdl"),
  Config.

make_wsdl(Hrl_file, Config) ->
  Data_dir = ?config(data_dir, Config),
  Hrl = filename:join(Data_dir, Hrl_file),
  %% create a wsdl on the working directory
  ok = soap:erlang2wsdl(Hrl, "service", "http://localhost:8080", [{wsdl_name, "service.wsdl"}]),
  Config.

correct_method() ->
  post.

correct_content_type() ->
  "text/xml;charset=UTF-8".

correct_headers() ->
  [{"SOAPAction", "com.esendex.ems.soapinterface/SendMessage"}].

correct_message() ->
  "<soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:com=\"com.esendex.ems.soapinterface\">\n"
  "   <soapenv:Header/>\n"
  "   <soapenv:Body>\n"
  "      <com:sendMessage>\n"
  "        <com:recipient>12345678</com:recipient>\n"
  "        <com:body>This is a test SMS</com:body>\n"
  "        <com:type>Text</com:type>\n"
  "     </com:sendMessage>\n"
  "  </soapenv:Body>\n"
  "</soapenv:Envelope>".

%% The handler module replies with a server fault if the 
%% type <> "Text"
client_error_message() ->
  "<soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:com=\"com.esendex.ems.soapinterface\">\n"
  "   <soapenv:Header/>\n"
  "   <soapenv:Body>\n"
  "      <com:sendMessage>\n"
  "        <com:recipient>ABCD</com:recipient>\n"
  "        <com:body>This is a test SMS</com:body>\n"
  "        <com:type>SMS</com:type>\n"
  "     </com:sendMessage>\n"
  "  </soapenv:Body>\n"
  "</soapenv:Envelope>".

invalid_xml_message() ->
  "<soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:com=\"com.esendex.ems.soapinterface\">\n"
  "   <soapenv:Header/>\n"
  "   <soapenv:body>\n"
  "      <com:sendMessage>\n"
  "        <com:recipient>12345678</com:recipient>\n"
  "        <com:body>This is a test SMS</com:body>\n"
  "        <com:type>Text</com:type>\n"
  "     </com:sendMessage>\n"
  "  </soapenv:Body>\n"
  "</soapenv:Envelope>".

unexpected_xml_message() ->
  "<soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:com=\"com.esendex.ems.soapinterface\">\n"
  "   <soapenv:Header/>\n"
  "   <soapenv:Body>\n"
  "      <com:sendMessage>\n"
  "        <com:recipient>123456789123456789</com:recipient>\n"
  "        <com:body>This is a test SMS</com:body>\n"
  "        <com:type>Text</com:type>\n"
  "     </com:sendMessage>\n"
  "  </soapenv:Body>\n"
  "</soapenv:Envelope>".

in_data_dir(Config, File) ->
  filename:join([?config(data_dir, Config), File]).

cowboy_version() ->
    Info = cowboy:module_info(),
    Exports = proplists:get_value(exports, Info),
    case proplists:get_value(start_tls, Exports) of
        4 ->
            soap_server_cowboy_2;
        undefined ->
            soap_server_cowboy_1
    end.
