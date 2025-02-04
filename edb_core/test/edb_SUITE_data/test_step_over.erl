-module(test_step_over).

-compile([warn_missing_spec_all]).

-export([go/1, cycle/2, just_sync/1, just_sync/2, call_closure/1, call_external_closure/1, catch_exception/1, raise_exception/1, awaiting_steps/0]).

%% Utility function to check executed lines

-spec sync(Controller :: pid(), Line :: pos_integer()) -> ok.
sync(Controller, Line) ->
    Me = self(),
    Controller ! {sync, Me, Line},
    ok.

%% Simple function

-spec go(Controller :: pid()) -> ok.
go(Controller) ->
    sync(Controller, ?LINE),
    sync(Controller, ?LINE),
    sync(Controller, ?LINE),
    sync(Controller, ?LINE),
    ok.

%% Inter-recursing clauses

-spec cycle(Controller :: pid(), left | right) -> none().
cycle(Controller, left) ->
    sync(Controller, ?LINE),
    cycle(Controller, right);
cycle(Controller, right) ->
    sync(Controller, ?LINE),
    cycle(Controller, left).

%% Arity overloading

-spec just_sync(Controller :: pid()) -> ok.
just_sync(Controller) ->
    sync(Controller, ?LINE),
    ok.

-spec just_sync(Controller :: pid(), unused_argument) -> ok.
just_sync(Controller, unused_argument) ->
    just_sync(Controller),
    ok.

%% Closures

-spec call_closure(Controller :: pid()) -> ok.
call_closure(Controller) ->
    sync(Controller, ?LINE),
    Ok = ok,
    (fun() ->
        sync(Controller, ?LINE),
        Ok
    end)(),
    sync(Controller, ?LINE),
    ok.

-spec call_external_closure(Controller :: pid()) -> ok.
call_external_closure(Controller) ->
    sync(Controller, ?LINE),
    F = make_closure(Controller),
    F(),
    sync(Controller, ?LINE),
    ok.

-spec make_closure(Controller :: pid()) -> fun(() -> ok).
make_closure(Controller) ->
    fun() ->
        sync(Controller, ?LINE),
        ok
    end.

-spec catch_exception(Controller :: pid()) -> ok.
catch_exception(Controller) ->
    sync(Controller, ?LINE),
    try
        indirect_raise_exception(Controller)
    catch
        error:oops ->
            sync(Controller, ?LINE),
            ok
    end.

-spec indirect_raise_exception(Controller :: pid()) -> no_return().
indirect_raise_exception(Controller) ->
    sync(Controller, ?LINE),
    raise_exception(Controller),
    unreachable.

-spec raise_exception(Controller :: pid()) -> no_return().
raise_exception(Controller) ->
    sync(Controller, ?LINE),
    error(oops),
    unreachable.

-spec awaiting_steps() -> ok.
awaiting_steps() ->
    await(),
    await(),
    await(),
    await(),
    ok.

-spec await() -> ok.
await() ->
    receive
        continue -> ok
    end.
