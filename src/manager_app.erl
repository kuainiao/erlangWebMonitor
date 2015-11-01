%%%-----------------------------------------------------------------------------
%%% Copyright (c) 2015-2016 Molmc, All Rights Reserved.
%%%
%%%-----------------------------------------------------------------------------
%%% @doc
%%% molmc network plateform monitor
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(manager_app).

-author("robertzhouxh@gmail.com").

-behaviour(application).

-export([start/2]).
-export([stop/1]).

%% Formats
-export([json_enc/1]).
-export([json_dec/1]).

%% Utils
-export([env/2]).
-export([env/3]).
-export([env_set/3]).
-export([env_set/4]).
-export([env_set/5]).

-export([prop/2]).
-export([prop/3]).
-export([prop_replace/3]).

-export([hex_to_bin/1]).
-export([bin_to_hex/1]).

-export([now/0]).
-export([parse_http_date/1]).

-export([set_auth/1]).

%% Debug
-export([stacktrace/0]).

-define(Filename, "auth.dat").

-type unixtime() :: integer().
-type route() ::
        {file, Path :: string()} |
        {dir, Path :: string()} |
        {priv_file, App :: atom(), Path :: string()} |
        {priv_dir, App :: atom(), Path :: string()} |
        {request, Module :: atom(), Function :: atom()} |
        {request, Module :: atom(), Function :: atom(), Protocol :: atom()} |
        {websocket, Handler :: atom(), Protocol :: atom()} |
        {websocket, Handler :: atom(), Protocol :: atom(), Timeout :: integer()}.


%% Setting up
start(_Type, _Args) ->
    Opts = application:get_all_env(manager),
    %% PrivDir = code:priv_dir(manager),
    TransOpts     = prop(ranch,  Opts, [{port, 8080}]), %% the port to be connected
    Routes        = prop(routes, Opts, []),             %% routing , dispatch

    CowboyOpts    = prop(cowboy, Opts, [{nb_acceptors, 100},
                                        {protocol, [{env, []}, {compress, true}]}
                                       ]),
    NbAcceptors   = prop(nb_acceptors, CowboyOpts),
    ProtoOpts     = prop(protocol,     CowboyOpts),

    %% ProtoEnvOpts ===> [{dispatch, routes(Routes)}]
    %% {HostMatch, list({PathMatch, Handler, Opts})}
    %% {'_', [{'_', my_handler, []}]}
    ProtoEnvOpts  = prop_replace(dispatch, prop(env, ProtoOpts, []), routes(Routes)),

    %% ProtoOpts2 ===> [{env, [{dispatch, routes(Routes)}]}, {compress, true}]
    ProtoOpts2    = prop_replace(env, ProtoOpts, ProtoEnvOpts),
    %% io:format("~p:~p starting erlangWebmonitor server on prort <  ~p  > ~n", [?MODULE, ?LINE, 8080]),
    lager:info("erlangWebmonitor starting ... on ===> ~n~p~n", [TransOpts]),
    %% lager:info("ProtoOpts2-------------: ~n~p~n", [ProtoOpts2]),
    %% cowboy:start_https(https, NbAcceptors, TransOpts, ProtoOpts2),
    cowboy:start_http(http, NbAcceptors, TransOpts, ProtoOpts2),

    %% you can start anyother server at this pointi ===> xxx_server:start_link(),

    manager_sup:start_link().

stop(_State) ->
    ok.

%% set username and Password   username:password
set_auth(Password)->
    {ok, PassHash} = get_hash_password(Password),
    
    {ok, S} = file:open("../files/auth.dat", write),
    io:format(S, "~s", [PassHash]),
    file:close(S),
    lager:info("PassHash ------------: ~n~p~n", [PassHash]).

%% Router match
-spec route({Pattern :: string(), Route :: route()}) -> tuple(). %% cowboy_router:route_rule()
route({Pattern, {dir, Path}}) ->
    {Pattern, cowboy_static, {dir, Path}};
route({Pattern, {priv_file, App, Path}}) ->
    {Pattern, cowboy_static, {priv_file, App, Path}};
route({Pattern, {priv_dir, App, Path}}) ->
    {Pattern, cowboy_static, {priv_dir, App, Path}};
route({Pattern, {request, Module, Function}}) ->
    {Pattern, sm_request, [{module, Module},
                           {function, Function}]};
route({Pattern, {request, Module, Function, Protocol}}) ->
    {Pattern, sm_request, [{module, Module},
                           {function, Function},
                           {protocol, Protocol}]};
route({Pattern, {websocket, Handler, Protocol}}) ->
    {Pattern, sm_websocket, [{handler, Handler},
                             {protocol, Protocol},
                             {timeout, 60000}]};
route({Pattern, {websocket, Handler, Protocol, Timeout}}) ->
    {Pattern, sm_websocket, [{handler, Handler},
                             {protocol, Protocol},
                             {timeout, Timeout}]}.

-spec routes(Routes :: cowboy_router:routes()) -> cowboy_router:dispatch_rules().
routes(Routes) ->
    Routes1 = [route(Route) || Route <- Routes],
    cowboy_router:compile(
      %% {HostMatch, PathsList} or {HostMatch, Constraints, PathsList}
      [{'_', [route({"/manager/[...]", {priv_dir, manager, "static"}})] ++ Routes1}]).

%% Formats
-spec json_enc(Data :: tuple()) -> list().
json_enc(Data) ->
    yaws_json2:encode(Data).

-spec json_dec(Data :: list()) -> tuple().
json_dec(Data) ->
    {ok, Document} = yaws_json2:decode_string(Data), Document.


%% Utils
-spec env(App :: atom(), Key :: atom()) -> any().
env(App, Key)          -> env(App, Key, undefined).
env(App, Key, Default) -> application:get_env(App, Key, Default).

-spec env_set(App :: atom(), Key :: atom(), Value :: any()) -> any().
-spec env_set(App :: atom(), Key :: atom(), Value :: any(), Timeout :: integer()) -> any().
-spec env_set(App :: atom(), Key :: atom(), Value :: any(), Timeout :: integer(), Persistent :: boolean()) -> any().
env_set(App, Key, Value)                      -> env_set(App, Key, Value, 5000, false).
env_set(App, Key, Value, Timeout)             -> env_set(App, Key, Value, Timeout, false).
env_set(App, Key, Value, Timeout, Persistent) -> application:set_env(App, Key, Value, [{timeout, Timeout}, {persistent, Persistent}]).

-spec prop(Key :: atom(), List :: [term()]) -> any().
prop(Key, List)          -> prop(Key, List, none).
prop(Key, List, Default) ->
    case lists:keyfind(Key, 1, List) of
        {_, Value} -> Value;
        _ -> Default
    end.

-spec prop_replace(Key :: atom(), List :: [term()], Value :: any()) -> [term()].
prop_replace(Key, List, Value) ->
    case lists:keyfind(Key, 1, List) of
        false -> [{Key, Value}|List];
        _ -> lists:keyreplace(Key, 1, List, {Key, Value})
    end.

-spec now() -> unixtime().
now() -> timestamp_to_unixtime(os:timestamp()).

-spec parse_http_date(Date :: binary() | string()) -> unixtime().
parse_http_date(Date) when is_list(Date) -> parse_http_date(list_to_binary(Date));
parse_http_date(Date)                    ->
    Seconds = calendar:datetime_to_gregorian_seconds(sm_date:parse_date(Date)) - 62167219200,
    Seconds * 1000.

-spec timestamp_to_unixtime(erlang:timestamp()) -> unixtime().
timestamp_to_unixtime({Mega, Sec, Micro}) ->
    (Mega * 1000000 + Sec) * 1000 + round(Micro/1000).


%%(c) Steve Vinoski
-spec bin_to_hex(Value :: binary()) -> binary().
bin_to_hex(Value) ->
    lists:flatten([io_lib:format("~2.16.0B", [X]) || X <- binary_to_list(Value)]).

-spec hex_to_bin(Bin :: binary() | string()) -> binary().
hex_to_bin(Value) when is_binary(Value) -> hex_to_bin(binary_to_list(Value), []);
hex_to_bin(Value) when is_list(Value)   -> hex_to_bin(Value, []).

hex_to_bin([], Acc)      -> list_to_binary(lists:reverse(Acc));
hex_to_bin([X,Y|T], Acc) ->
    {ok, [V], []} = io_lib:fread("~16u", [X,Y]),
    hex_to_bin(T, [V | Acc]).


%% Debug
stacktrace() ->
    Trace = try throw(sm_stacktrace) catch sm_stacktrace -> erlang:get_stacktrace() end,
    erlang:display(Trace).

%% On success, returns {ok, Hash}.
get_hash_password(Password)->
    {ok, Salt} = bcrypt:gen_salt(),
    bcrypt:hashpw(Password, Salt).
