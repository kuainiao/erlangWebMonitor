%%% File: my_http_module.erl
%%% Author: Xuehao Zhou <robertzhouxh.github.io>
%%%
%%% Created: Wednesday, October 21 2015

-module(my_http_proto_module).

-include("../include/sm.hrl").

-export([my_http_proto_handler/2, delete_all/2, mongofind/3]).

%% Information of databases
%% -define(RDDB_INDEX, 1).            %% Index of redis databases
-define(MSQL_USER_TAB,).  %% Table that stores the Information of users
-define(DAYTS, 86400).

my_http_proto_handler(Decoded, Req) ->
    %% lager:info("~p:~p my_http_proto_handler Decoded:  ~p", [?MODULE, ?LINE, Decoded]),
    {Action, Req2} = cowboy_req:binding(action, Req),
    {Method, Req3} = cowboy_req:method(Req2),

    {Status, Reply, Cookies, Headers, ReqTail} = enter_handlers(Action,
                                                                binary_to_list(Method),
                                                                Req3,
                                                                Decoded
                                                               ),
    %% lager:info("Req3 ---------------> ~n~p~n", [Req3]),
    %% lager:info("~p:~p tobe sent to sm:  ~p", [?MODULE, ?LINE, Reply]),
    {ok, Reply, #sm_response{status  = Status, headers = Headers, cookies = Cookies}, ReqTail}.

%% Handlers
enter_handlers(Action, Method, Req, Payload) ->
    case Action of
        <<"login">> when Method =:= "POST" ->
            lager:info("starting ~p process", [Action]),
            login_handler(Req, Payload);
        <<"logout">> when Method =:= "GET" ->
            lager:info("starting ~p process", [Action]),
            logout_handler(Req);
        <<"users">> when Method =:= "GET" ->
            lager:info("starting ~p process", [Action]),
            case check_session(Req) of
                {undefined, Req2} ->
                    redirect_to(Req2, <<"Login again!">>, ?LOGIN_URL);
                {_SessionVal, Req2} ->
                    users_handler(Req2)
            end;
        <<"online">> when Method =:= "GET" ->
            lager:info("starting ~p process", [Action]),
            case check_session(Req) of
                {undefined, Req2} ->
                    redirect_to(Req2, <<"Login again!">>, ?LOGIN_URL);
                {_SessionVal, Req2} ->
                    online_handler(Req2)
            end;
        <<"devices">> when Method =:= "GET" ->
            lager:info("starting ~p process", [Action]),
            case check_session(Req) of
                {undefined, Req2} ->
                    redirect_to(Req2, <<"Login again">>, ?LOGIN_URL);
                {_SessionVal, Req2} ->
                    devices_handler(Req2)
            end;
        <<"logs">> when Method =:= "GET" ->
            lager:info("starting ~p process", [Action]),
            case check_session(Req) of
                {undefined, Req2} ->
                    redirect_to(Req2, <<"Login again">>, ?LOGIN_URL);
                {_SessionVal, Req2} ->
                    log_handler(Req2)
            end;
        _ ->
            lager:info("Invalid Request For ~p and redirect to URL: ~s", [Action, "/"]),
            redirect_to(Req, Payload, ?INDEX_URL)
    end.


%% Erlang term() will be encoded into Json Object:
%% jsx:encode([{<<"library">>,<<"derp">>},{<<"awesome">>,<<"nerp">>},{<<"IsAwesome">>,<<"ME">>}]);
login_handler(Req, [{<<"username">>, Username}, {<<"password">>, Password}]) ->
    ok = cowboy_session_config:set(cookie_options, [{path, <<"/">>}]),
    ok = cowboy_session_config:set([{cookie_name, <<"sessionid">>}, {expires, 86400}]),
    Src = binary_to_list(Username) ++ ":" ++ binary_to_list(Password),
    %% lager:info("~p:~p SRC: ~p", [?MODULE, ?LINE, Src]),
    %% {ok, Pwdhash} = hash_password("admin:pass"),
    {ok, S} = file:open("../files/auth.dat", read),
    Pwdhash = io:get_line(S, ''),
    %% lager:info("~p:~p Pwdhash: ~p", [?MODULE, ?LINE, Pwdhash]),

    case check_password(Src, Pwdhash) of    %% verify the Password
        true -> case set_session(Req) of
                    {ok, Req3}->
                        %% lager:info("~p:~p Req3 ==============>  ~p", [?MODULE, ?LINE, Req3]),
                        {200,
                         [{<<"msg">>, <<"Login successfully!">>}],
                         [],
                         [{<<"content-type">>, <<"application/json">>}],
                         Req3}
                end;
        false -> {401,                                   %% Status
                  [{<<"msg">>, <<"Login Failed!">>}],    %% Reply
                  [],                                    %% Cookie
                  [{<<"content-type">>, <<"application/json">>}], %% Headers
                  Req}                                            %% ReqTail
    end.

logout_handler(Req) ->
    case cowboy_session:expire(Req) of
        {ok, Req2} ->
            {200, [{<<"msg">>, <<"Logout!">>}], [], [], Req2}
    end.

users_handler(Req) ->
    {ok, Pars} = application:get_env(manager, readusers),
    {_, UserTable} = lists:keyfind(users_table, 1, Pars),
    {_, SearchDays} = lists:keyfind(search_days, 1, Pars),
    UsersInfo = get_userinfo_from_mysql(UserTable, SearchDays),
    Resp = UsersInfo,
    {200,
     Resp,
     [],
     [{<<"content-type">>, <<"application/json">>}],
     Req}.

online_handler(Req) ->
    {ok, Pars} = application:get_env(manager, readsesses),
    {_, PoolId} = lists:keyfind(poolid, 1, Pars),
    {_, DbIndex} = lists:keyfind(sess_redis_index, 1, Pars),
    Resp = case get_session_from_redis(PoolId, DbIndex) of
               {ok, [Record]} ->
                   Record;
               {ok, Tuple} ->
                   Tuple;
               _ ->
                   lager:info("-------can not find [key] in redis ----------------")
           end,
    {200,
     Resp,
     [],
     [{<<"content-type">>, <<"application/json">>}],
     Req}.

devices_handler(Req) ->
    {ok, Pars} = application:get_env(manager, readdevs),
    Database = lists:keyfind(database, 1, Pars),
    {_, Collection} = lists:keyfind(collection, 1, Pars),
    Host = lists:keyfind(host, 1, Pars),
    Port = lists:keyfind(port, 1, Pars),
    {_, SearchDays} = lists:keyfind(search_days, 1, Pars),
    DevicesInfo = get_devices_from_mongo(Host, Port, Database, Collection, SearchDays),
    Resp = DevicesInfo,
    {200,
     Resp,
     [],
     [{<<"content-type">>, <<"application/json">>}],
     Req}.

log_handler(Req)->
    {ok, Pars} = application:get_env(manager, readlog),
    Host = lists:keyfind(host,1,Pars),
    Port = lists:keyfind(port, 1, Pars),
    Database = lists:keyfind(database, 1, Pars),
    {_, Collection} = lists:keyfind(collection, 1, Pars),
    LogInfo = get_logs_from_mongo(Host, Port, Database, Collection),
    Resp = LogInfo,
    {200,
     Resp,
     [],
     [{<<"content-type">>, <<"application/json">>}],
     Req}.

get_session_from_redis(PoolId, DbIndex) ->
    eredis_pool:q(PoolId, ["select",DbIndex]),
    {ok, SessAgentKeys} = eredis_pool:q({global, pool1},["keys", "web:agents:*"]),
    %% lager:info("SessAgentKeys ============> ~p~n", [SessAgentKeys]), % get all agents keys, eg. web:agents:hui@molmc.com
    {ok, SessKeys} = get_hash_val(SessAgentKeys),
    %% lager:info("SessKeys ========> ~p~n", [SessKeys]),
    SessAppKeys0 = lists:map(fun(SessKey) ->
                                     case lists:keyfind(<<"app">>, 1, SessKey) of
                                         {_, LoginApp}->
                                             LoginApp;
                                         false ->  false
                                     end
                             end,   SessKeys),
    SessBwsKeys0 = lists:map(fun(SessKey) ->
                                     case lists:keyfind(<<"browser">>, 1, SessKey) of
                                         {_, LoginBws}->
                                             LoginBws;
                                         false ->  false
                                     end
                             end,  SessKeys),

    SessBwsKeys = lists:delete(false, SessBwsKeys0), % [sessionids] in browser
    SessAppKeys = lists:delete(false, SessAppKeys0), % [sessionids] in app
    {ok, SessBws} = get_hash_val(SessBwsKeys, <<"browser">>),
    {ok, SessApp} = get_hash_val(SessAppKeys, <<"app">>),
    NumLogBws = erlang:length(SessBws),
    NumLogApp = erlang:length(SessApp),
    Sessions =[{total_browser, NumLogBws},
              {total_app, NumLogApp},
              {users, lists:append(SessBws,SessApp)}],
    {ok, Sessions}.

get_userinfo_from_mysql(MSQL_USER_TAB, SEARCH_DAYS) ->
    SelTotalNum = "select count(*) from " ++ atom_to_list(MSQL_USER_TAB),
    SelDaysInfo = "SELECT regdate, email, username FROM " ++ atom_to_list(MSQL_USER_TAB) 
                   ++ " order by " ++ " regdate desc limit " ++ integer_to_list(SEARCH_DAYS),
    {ok, [[{_, NumTotalUsers}]]} = emysql:sqlquery(SelTotalNum),
    {ok, DaysUsersInfo} = emysql:sqlquery(SelDaysInfo),
    %% lager:info("NumTotalUsers ============> ~p~n", [NumTotalUsers]),
    %% lager:info("DaysUsersInfo ============> ~p~n", [DaysUsersInfo]),
    _UsersInfo =[{pc_total, NumTotalUsers},
                {app_total, 0},
                {days_users, DaysUsersInfo}].

get_devices_from_mongo(Host, Port, Database, Collection, SearchDays) ->
    {ok, Connection} = mongo:connect ([Database, Host, Port]),

    TodayBeginTimeYMDHMS = {erlang:date(), {0,0,0}},
    TodayBeginTimeStamp = calendar:datetime_to_gregorian_seconds(TodayBeginTimeYMDHMS) 
                          - calendar:datetime_to_gregorian_seconds({{1970,1,1}, {0,0,0}}),
    %% lager:info("DayBeginTimeStamp ============> ~p~n", [TodayBeginTimeStamp]),

    SelAllDevsNum = {},
    SelNewRegInfo = {<<"created_at">>, {'$gte', TodayBeginTimeStamp - SearchDays * ?DAYTS}},
    SelNewPubInfo = {'$and', [{<<"created_at">>, {'$gte', TodayBeginTimeStamp - SearchDays * ?DAYTS}}, 
                              {<<"isPublic">>, true}]},
    %% search relative numbers of devices
    NumOfTatalDev = mongo:count(Connection, Collection, SelAllDevsNum),
    %% TODO: search the public devices of newly built
    NumOfPubDev = 0,                            % intead in the future
    RawNewRegInfo = mongofind(Connection, Collection, SelNewRegInfo),
    RawNewPubInfo = mongofind(Connection, Collection, SelNewPubInfo),
    NewRegInfo = lists:map(fun(M) ->
                                   maps:remove(<<"_id">>, M) end, RawNewRegInfo),
    NewPubInfo = lists:map(fun(M) ->
                                   maps:remove(<<"_id">>, M) end, RawNewPubInfo),
    _Devices =[{total_devs, NumOfTatalDev},
              {public_devs, NumOfPubDev},
              {days_new_devs, NewRegInfo},
              {days_pub_devs, NewPubInfo}].


get_logs_from_mongo(Host, Port, Database, Collection)->
    {ok, Connection} = mongo:connect ([Database, Host, Port]),
    RawLogInfo = mongofind(Connection, Collection, {}),
    LogInfo = lists:map(fun(M) ->
                                maps:remove(<<"_id">>, M)
                        end, RawLogInfo),
    LogInfo.

%% ------------------------------------------------------------------------------------------------------
check_session(Req) ->
    {_SessionId, Req2} = cowboy_req:cookie(<<"sessionid">>, Req), %% read the value of cookie
    {SomeVal, Req3} = cowboy_session:get(<<"somekey">>, Req2),
    %% lager:error("~p:~p get the SessionId:~p ~n sessionVal:~p", [?MODULE, ?LINE, <<"somekey">>, SomeVal]),
    {SomeVal, Req3}.

%% generate a cookies in the Req
set_session(Req) ->
    Key = <<"somekey">>,
    Val = <<"someval">>,
    {ok, Req2} = cowboy_session:set(Key, Val, Req),
    {ok, Req2}.

redirect_to(Req, Reply, Location) ->
    %% {401, Reply, [], [{<<"Location">>, Location}], Req},
    {401,                                   %% Status
     [{<<"msg">>, <<"Login again!">>}],    %% Reply
     [],                                    %% Cookie
     [{<<"content-type">>, <<"application/json">>}], %% Headers
     Req}.

%% @Password is the Hash of the right password
check_password(PasswordAttempt, PasswordHash) ->
    StoredPassword = PasswordHash,
    %% lager:info("~p:~p check ... StoredPassword ~p", [?MODULE, ?LINE, StoredPassword]),
    compare_password(PasswordAttempt, StoredPassword).

compare_password(PasswordAttempt, PasswordHash) ->
    {ok, PasswordHash} =:= bcrypt:hashpw(PasswordAttempt, PasswordHash).

%% On success, returns {ok, Hash}.
hash_password(Password)->
    {ok, Salt} = bcrypt:gen_salt(),
    bcrypt:hashpw(Password, Salt).

replvar(AuthSql, Username) ->
    re:replace(AuthSql, "%u", Username, [global, {return, list}]).

%% get value from agents keys, eg  web:agents:hui@molmc.com
get_hash_val(Keys) ->
    KVs = lists:map(fun(Key) ->
                            {ok, Keyi} = eredis_pool:q({global, pool1}, ["HKEYS", Key]), % is "browser" or "app"
                            {ok, Vali} = eredis_pool:q({global, pool1}, ["HVALS", Key]), % is relative sesseionid
                            _LT = lists:zip(Keyi, Vali)
                    end,
                    Keys),                      % Keys is  "web:agents:*"
    {ok, KVs}.  % eg KVs = {"browser" "web:sess:2b8bc142e62c8adaadac08b93a481a44"}

%% Keys = [sessionids]
get_hash_val(Keys, InDev) ->
    KVs = lists:map(fun(Key) ->
                            {ok, Keyi} = eredis_pool:q({global, pool1}, ["HKEYS", Key]),
                            {ok, Vali} = eredis_pool:q({global, pool1}, ["HVALS", Key]),
                            _LT = lists:zip([login_dev|Keyi],[InDev|Vali])
                    end,
                    Keys),
    FilterFactor = [{login_dev, InDev}],
    KVs_no_undif = delete_all(FilterFactor, KVs),
    {ok, KVs_no_undif}.

mongofind(Connection, Collection, Selector)->
    Cursor = mongo:find(Connection, Collection, Selector),
    Result = mc_cursor:rest(Cursor),
    mc_cursor:close(Cursor),
    Result.

%% delete all X in list L
delete_all(X, [X|T]) ->
    delete_all(X, T);
delete_all(X, [Y|T]) ->
    [Y | delete_all(X, T)];
delete_all(_, []) ->
    [].
