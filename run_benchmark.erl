%% -*- erlang-indent-level: 2 -*-
-module(run_benchmark).
-export([run/1]).
-export([time_now/0, time_since/1]).

run([M, Mode]) ->
  bench_file(M, Mode).

bench_file(File, Mode) ->
  case File of
    prettypr ->
      case get(prettypr_data) of
	undefined -> {ok,[X]} =
	  file:consult("prettypr.input"),
	  put(prettypr_data, X),
	  ok;
	_ -> ok
      end;
    _ -> ok
  end,
  ok = compile(File, Mode),
  io:format("~w~n", [run_bench(File)]).

compile(_File, beam) ->
  ok;
compile(File, hipe) ->
  {ok, File} = hipe:c(File, [{regalloc,coalescing}, o2]),
  ok;
compile(File, erllvm) ->
  {ok, File} = hipe:c(File, [o2, to_llvm]),
  ok.

run_bench(File) ->
  Myself = self(),
  Opts = [], %[{min_heap_size, 100000000}],
  spawn_opt(fun () ->
        % Supress IO
        {ok, F} = file:open("result_file", [write]),
        group_leader(F, self()),
        T1 = run_benchmark:time_now(),
        try
          File:main([integer_to_list(File:medium())])
        catch
          exit:ok -> ok;
          _:_ -> Myself ! -1
        end,
        Myself ! run_benchmark:time_since(T1),
        file:close(F)
        end, Opts),
  receive
    Result -> Result
  end.

time_now() ->
  erlang:now().

time_since(T1) ->
  T2 = erlang:now(),
  timer:now_diff(T2, T1)/1000. % Return millisecs
