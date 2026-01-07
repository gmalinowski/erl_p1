-module(event).
-compile(export_all).
-record(state, {server, name="", to_go=[]}).


start(EventName, DateTime) ->
    spawn(?MODULE, init, [self(), EventName, DateTime]).

start_link(EventName, DateTime) ->
    spawn_link(?MODULE, init, [self(), EventName, DateTime]).

cancel(Pid) ->
    Ref = erlang:monitor(process, Pid),
    Pid ! {self(), Ref, cancel},
    receive
        {Ref, ok} ->
            erlang:demonitor(Ref, [flush]),
            ok;
        {'DOWN', Ref, process, Pid, _Reason} ->
            ok
    end.

init(Server, EventName, DateTime) ->
    loop(#state{server=Server, name=EventName, to_go=seconds_to_go(DateTime)}).

seconds_to_go(TimeOut={{_,_,_}, {_,_,_}}) ->
    Now = calendar:local_time(),
    ToGo = calendar:datetime_to_gregorian_seconds(TimeOut) - calendar:datetime_to_gregorian_seconds(Now),
    if ToGo =< 0 -> 0;
        true -> normalize_time(ToGo)
end.



normalize_time(N) ->
    Limit = 49 * 24 * 60 * 60,
    [N rem Limit | lists:duplicate(N div Limit, Limit)].

loop(S = #state{server=Server, to_go=[T|Next]}) ->
    receive
        {Server, Ref, cancel} ->
            Server ! {Ref, ok}
        after T*1000 ->
            if Next =:= [] ->
                Server ! {done, S#state.name};
            Next =/= [] ->
                loop(S#state{to_go=Next})
            end
    end.