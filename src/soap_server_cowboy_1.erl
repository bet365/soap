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

%%% Implementation of the interface between the SOAP framework and the
%%% Cowboy HTTP server, version 1.0.x
%%%
%%% Starts and stops the server, and acts as the 
%%% entry point for each request (the 'init' function).
%%%
%%% Routes to the requests to the SOAP sub protocol.
%%%
%%% To start cowboy embedded, generate a child spec using 
%%% ranch:child_spec().
%%%
%%% For example:
%%%
%%% soap_child_spec(Module, Options) ->
%%%     Port = 8080,
%%%     Acceptor_count = 100,
%%%     Max_connections = 1000,
%%%     Id = "soap_interface"
%%%     Transport = ranch_tcp,
%%%     Transport_options = [{port, Port},
%%%                          {max_connections, Max_connections},
%%%                          {backlog, 1024}],
%%%     Protocol = cowboy_protocol,
%%%     %% The exact routing  depends on your situation:
%%%     %% url(s) for the SOAP service(s), other things the
%%%     %% server does. The example below routes all requests to the 
%%%     %% SOAP service.
%%%     Dispatch = cowyboy_router:compile([
%%%         {'_', [{'_', soap_server_cowboy_1, {Module, Options}}]}]),
%%%     Protocol_options = [{timeout, 5000},
%%%                         {env, [{dispatch, Dispatch}]}],
%%%     ranch:child_spec(Id, Acceptor_count, Transport, 
%%%                      Transport_options, Protocol, Protocol_options).
%%%
-module(soap_server_cowboy_1).

-export([start/1]).
-export([start/2]).
-export([stop/0]).
-export([init/3]).

start(Module) ->
    start(Module, []).

start(Module, Options) ->
  Port = proplists:get_value(port, Options, 8080),
  Acceptors = proplists:get_value(nr_acceptors, Options, 100),
  {ok, _} = application:ensure_all_started(cowboy),
  Dispatch = cowboy_router:compile([
                                    {'_', [{'_', ?MODULE, {Module, Options}}]}]),
  {ok, _} = cowboy:start_http(http, Acceptors, [{port, Port}],
                              [{env, [{dispatch, Dispatch}]}]).

stop() ->
    cowboy:stop_listener(http),
    application:stop(cowboy), 
    application:stop(ranch).

%% This is called by cowboy for each request. 
init(_, _Req, {_Module, _Options}) ->
    %% The module 'soap_cowboy_protocol' will be called
    %% for each request, with Module (= the handler module) and 
    %% the options as parameter. 
    {upgrade, protocol, soap_cowboy_1_protocol}.

