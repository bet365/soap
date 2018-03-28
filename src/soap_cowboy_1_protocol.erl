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
%%% SOAP handler for Cowboy, v.1. 
%%% Takes care of the SOAP specific stuff such as decoding and encoding the
%%% xml, some error handling on the level of the soap protocol, etc.
%%%

-module(soap_cowboy_1_protocol).
%% -behaviour(cowboy_sub_protocol).

-export([upgrade/4, upgrade/5]).
-export([enrich_req/2]).
-export([respond/4]).

-type cowboy_req() :: cowboy_req:req().
-type cowboy_env() :: cowboy_middleware:env().

%%% ============================================================================
%%% Exported functions
%%% ============================================================================

%% This is the callback of the cowboy_sub_protocol behaviour.
%%
%% From the Cowboy documentation:
%% This callback is expected to behave like a middleware and to return an
%% updated req object and environment.
-spec upgrade(Cowboy_req::cowboy_req(), Env::cowboy_env(),
              Soap_handler::module(), 
              {Implementation_handler::module(), Options::any()}) -> 
    {ok, cowboy_req(), cowboy_env()}. 
upgrade(Cowboy_req, Env, Soap_handler, {Handler, Options}) ->
  {ok, Message, Cowboy_req2} = cowboy_req:body(Cowboy_req),
  upgrade(Cowboy_req2, Env, Soap_handler, {Handler, Options}, Message).

%% There might exist middleware that reads body from the cowboy_req, in which 
%% case it will be no longer available while calling upgrade/4. In this case
%% you are responsible for propogating Body directly to upgrade/5
-spec upgrade(Cowboy_req::cowboy_req(), Env::cowboy_env(),
              Soap_handler::module(), 
              {Implementation_handler::module(), Options::any()}, Body::binary()) -> 
                                                               {ok, cowboy_req(), cowboy_env()}. 
upgrade(Cowboy_req, Env, Soap_handler, {Handler, Options}, Message) ->
  soap_cowboy_protocol:upgrade(Cowboy_req, Env, Soap_handler, 
                               {Handler, Options}, cowboy_1, ?MODULE, Message).

enrich_req(Cowboy_req, Soap_req) ->
  {Method, Req2} = cowboy_req:method(Cowboy_req),
  Soap_req2 = soap_req:set_method(Soap_req, make_list(Method)),
  {Content_type, Req3} = cowboy_req:header(<<"content-type">>, Req2),
  Soap_req3 = soap_req:set_content_type(Soap_req2, make_list(Content_type)),
  {Soap_action, Req4} = cowboy_req:header(<<"soapaction">>, Req3),
  Soap_req4 = soap_req:set_soap_action(Soap_req3, make_list(Soap_action)),
  soap_req:set_server_req(Soap_req4, Req4).

respond(Cowboy_req, Env, _Handler, StatusCode) ->
  {ok, Req2} = cowboy_req:reply(StatusCode, Cowboy_req),
  terminate(Req2, Env).

%%% ============================================================================
%%% Internal functions
%%% ============================================================================

make_list(undefined) ->
  undefined;
make_list(Binary) ->
  binary_to_list(Binary).

terminate(Cowboy_req, Env) ->
  {ok, Cowboy_req, Env}.
