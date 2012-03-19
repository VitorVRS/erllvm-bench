%% file: "length_u.erl"

-module(length_u).
-export([test/0,compile/1]).

len(L) -> len(0,L).

len(X,[_|[_|[_|[_|[_|[_|[_|[_|[_|[_|[_|T]]]]]]]]]]]) -> len(X+1,T);
len(X,[_|[_|[_|[_|[_|[_|[_|[_|[_|[_|T]]]]]]]]]]) -> len(X+1,T);
len(X,[_|[_|[_|[_|[_|[_|[_|[_|[_|T]]]]]]]]]) -> len(X+1,T);
len(X,[_|[_|[_|[_|[_|[_|[_|[_|T]]]]]]]]) -> len(X+1,T);
len(X,[_|[_|[_|[_|[_|[_|[_|T]]]]]]]) -> len(X+1,T);
len(X,[_|[_|[_|[_|[_|[_|T]]]]]]) -> len(X+1,T);
len(X,[_|[_|[_|[_|[_|T]]]]]) -> len(X+1,T);
len(X,[_|[_|[_|[_|T]]]]) -> len(X+1,T);
len(X,[_|[_|[_|T]]]) -> len(X+1,T);
len(X,[_|[_|T]]) -> len(X+1,T);
len(X,[_|T]) -> len(X+1,T);
len(X,[]) -> X.

make_list(X) -> make_list(X,[]).
make_list(0,L) -> L;
make_list(X,L) -> make_list(X-1,[0|L]).

loop(0,_,R) -> R;
loop(N,L,_) -> loop(N-1,L,len(L)).

test() ->
    L = make_list(20000),
    T1 = run_benchmark:time_now(),
    _R = loop(50000,L,0),
    Time = run_benchmark:time_since(T1),
    %% io:format("~w\t",[Time]),
    Time.

compile(Flags) ->
    hipe:c(?MODULE,Flags).
