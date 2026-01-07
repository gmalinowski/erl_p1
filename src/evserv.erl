-module(evserv).
-compile(export_all).

-record(state, {events, clients}).
-record(event, {
    name="",
    description="",
    pid,
    datetime={{1970,1,1}, {0,0,0}}
    }).

init() ->
    loop(#state{events=orddict:new(), clients=orddict:new()}).

loop(S = #state{}) ->
    receive
        {Pid, MsgRef, {subscribe, Client}} ->
            Ref = erlang:monitor(process, Client),
            NewClients = orddict:store(Ref, Client, S#state.clients),
            Pid ! {MsgRef, ok},
            loop(S#state{clients=NewClients});
        {Pid, MsgRef, {add, Name, Description, TimeOut}} ->
            case valid_datetime(TimeOut) of
                true ->
                    EventPid = event:start_link(Name, TimeOut),
                    NewEvents = orddict:store(Name, #event{
                        name=Name,
                        description=Description,
                        pid=EventPid,
                        datetime=TimeOut
                    }, S#state.events),
                    Pid ! {MsgRef, ok},
                    loop(S#state{events=NewEvents});
                false ->
                    Pid ! {MsgRef, {error, invalid_datetime}},
                    loop(S)
            end;
        {Pid, MsgRef, {cancel, Name}} ->
            Events = case orddict:find(Name, S#state.events) of
                {ok, Evt} ->
                    event:cancel(Evt#event.pid),
                    orddict:erase(Name, S#state.events);
                error ->
                    S#state.events
            end,
            Pid ! {MsgRef, ok},
            loop(S#state{events=Events});
        {done, Name} ->
            case orddict:find(Name, S#state.events) of
                {ok, Evt} ->
                    notify_clients({done, Evt#event.name, Evt#event.description},
                                   S#state.clients),
                    NewEvents = orddict:erase(Name, S#state.events),
                    loop(S#state{events=NewEvents});
                error ->
                    loop(S)
            end;
        shutdown ->
            exit(shutdown);
        {'DOWN', Ref, process, _Pid, _Reason} ->
            NewClients = orddict:erase(Ref, S#state.clients),
            loop(S#state{clients=NewClients});
        code_change ->
            ?MODULE:loop(S);
        Unknown ->
            io:format("evserv: unknown message ~p~n", [Unknown]),
            loop(S)
    end.

notify_clients(Msg, Clients) ->
    orddict:map(fun(_Ref, Pid) ->
        Pid ! Msg
    end, Clients).

valid_datetime({Date, Time}) ->
    try 
        calendar:valid_date(Date) andalso valid_time(Time)
    catch
        _:_ -> false
    end;
valid_datetime(_) ->
    false.

valid_time({H, M, S}) when H >= 0, H < 24,
                                    M >= 0, M < 60,
                                    S >= 0, S < 60 -> true;
valid_time(_) -> false.