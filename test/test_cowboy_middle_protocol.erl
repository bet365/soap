-module(test_cowboy_middle_protocol).

-export([start/2]).
-export([stop/0]).
-export([init/3, init/2]).
-export([on_request/1]).
-export([execute/2]).
-export([upgrade/4]).


start(Module, Options) ->
  Port = proplists:get_value(port, Options, 8080),
  {ok, _} = application:ensure_all_started(cowboy),
  Dispatch = cowboy_router:compile([
                                    {'_', [{'_', ?MODULE, {Module, Options}}]}]),

  case proplists:get_value(cowboy_version, Options) of
    soap_server_cowboy_1 ->
      cowboy:start_http(http, 10, [{port, Port}],
                        [ {env, [{dispatch, Dispatch}]},
                          {onrequest, fun ?MODULE:on_request/1}
                        ]);
    soap_server_cowboy_2 ->
      cowboy:start_clear(http, [{port, Port}],
                         #{env => #{dispatch => Dispatch},
                           middlewares => [ cowboy_router
                                          , ?MODULE
                                          , cowboy_handler
                                          ]
                          }
                        )
  end.

stop() ->
  cowboy:stop_listener(http),
  application:stop(cowboy),
  application:stop(ranch).

on_request(Req0) ->
  {ok, Body, Req1} = cowboy_req:body(Req0),
  cowboy_req:set_meta(body, Body, Req1).

execute(Req, Env) ->
  {ok, Body, Req1} = cowboy_req:read_body(Req),
  {ok, Req1, maps:put(req_body, Body, Env)}.

%% cowboy 1 callback
init(_, _Req, {_Module, Options}) ->
  %% The module 'soap_cowboy_protocol' will be called
  %% for each request, with Module (= the handler module) and
  %% the options as parameter.
  soap_server_cowboy_1 = proplists:get_value(cowboy_version, Options),
  {upgrade, protocol, ?MODULE}.

%% cowboy 2 callback
init(Req, {Module, Options}) ->
  soap_server_cowboy_2 = proplists:get_value(cowboy_version, Options),
  {?MODULE, Req, {Module, Options}}.

upgrade(Cowboy_req, Env, Soap_handler, {Handler, Options}) ->
  case proplists:get_value(cowboy_version, Options) of
    soap_server_cowboy_1 ->
      Options2 = proplists:delete(cowboy_version, Options),
      {Message, Cowboy_req2} = cowboy_req:meta(body, Cowboy_req),
      soap_cowboy_1_protocol:upgrade(Cowboy_req2, Env, Soap_handler, {Handler, Options2}, Message);
    soap_server_cowboy_2 ->
      Options2 = proplists:delete(cowboy_version, Options),
      Message = maps:get(req_body, Env),
      soap_cowboy_2_protocol:upgrade(Cowboy_req, Env, Soap_handler, {Handler, Options2}, Message)
  end.
