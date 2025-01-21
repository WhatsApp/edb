-module(test_step_out).

-compile([warn_missing_spec_all]).

-export([go/1, cycle/2, just_sync/1, just_sync/2, call_closure/1, call_external_closure/1]).

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
