%% -*- erlang-indent-level: 2 -*-
-module(run_benchmark).

-export([run/1]).

-include("stats.hrl").

run([Metric, Class, Module, Comp, N]) ->
  bench_file(Metric, Class, Module, Comp, list_to_integer(atom_to_list(N))).


bench_file(Metric, Class, File, Comp, N) ->
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
  T = run_bench(Metric, Class, Comp, File, N),
%  io:format("DEBUG: File: ~p~n", [T]),
  %% Write results/errors to files:
  ResFile = lists:concat(["results/", Metric, "_", Comp, ".res"]),
  file:write_file(ResFile, io_lib:fwrite("~w\t~.3f\n", [File, T#stat.median])
                  , [append]),
  ErrFile = lists:concat(["results/", Metric, "_", Comp, "-err.res"]),
  file:write_file(ErrFile, io_lib:fwrite("~w\t~.3f\n", [File, T#stat.stddev])
                  , [append]).

run_bench(runtime, _Class, _Comp, File, N) when is_integer(N) ->
  Myself = self(),
  Opts = [], %[{min_heap_size, 100000000}],
  Size = medium,
%  io:format("DEBUG: Module: ~p - info(): ~p~n", [File, File:module_info()]),
  ModExports = element(2, lists:keyfind(exports, 1, File:module_info())),
  Args =
    case lists:member({Size,0}, ModExports) of
      true -> File:Size();
      false -> []
    end,
  spawn_opt(fun () ->
                %% Supress IO
                {ok, F} = file:open("io_file", [write]),
                group_leader(F, self()),
                %% Use a runner in order to catch the exiting exception.
                Runner = fun () -> try
                                     File:main(Args)
                                   catch
                                     exit:ok -> ok;
                                     _:_ -> badexit
                                   end
                         end,
                Times = stats:test_avg(Runner, [], N),
                Myself ! Times,
                file:close(F)
            end, Opts),
  receive
    Result -> Result
  end;

run_bench(compile, Class, Comp, File, N) ->
  ErlFile = lists:concat(["src/", Class, "/", File, ".erl"]),
  Myself = self(),
  Opts = [],
  spawn_opt(fun () ->
                %% Supress IO
                {ok, F} = file:open("io_file", [write]),
                group_leader(F, self()),
                %% Use a runner in order to catch the exiting exception.
                Runner = fun () -> try
                                       Options = case Comp of
                                           hipe ->
                                               [native, {hipe, [{regalloc,coalescing},o2]}, {outdir, "ebin"}];
                                           erllvm ->
                                               [native, {hipe, [o2,to_llvm]}, {outdir, "ebin"}];
                                           _ ->
                                               [{outdir, "ebin"}]
                                       end,
                                       compile:file(ErlFile, Options)
                                   catch
                                     exit:ok -> ok;
                                     _:_ -> badexit
                                   end
                         end,
                Times = stats:test_avg(Runner, [], N),
                Myself ! Times,
                file:close(F)
            end, Opts),
  receive
    Result -> Result
  end;

run_bench(size, Class, Comp, File, _N) ->
  ErlFile = lists:concat(["src/", Class, "/", File, ".erl"]),
  Options = case Comp of
                hipe ->
                    [native, {hipe, [{regalloc,coalescing},o2]}, {outdir, "ebin"}];
                erllvm ->
                    [native, {hipe, [o2,to_llvm]}, {outdir, "ebin"}];
                _ ->
                    [{outdir, "ebin"}]
            end,
  c:c(ErlFile, Options),
  Size = File:module_info(size) / 1,
  S = #stat{median = Size,
            average = Size,
            stddev = 0.0},
  S.

