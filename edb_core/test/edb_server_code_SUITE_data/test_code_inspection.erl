-module(test_code_inspection).

% elp:ignore compile-warn-missing-spec

-export([go/1, cycle/2, just_sync/1, just_sync/2, make_closure/1, id/1, swap/1]).

%% Define a dummy sync to have code similar to the other test fixtures
-spec sync(Controller :: pid(), Line :: integer()) -> ok.
sync(_Controller, _Line) -> ok.

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

%% Ends on a "non-executable" line (`end.`)

-spec make_closure(Controller :: pid()) -> fun(() -> ok).
make_closure(Controller) ->
    fun() ->
        sync(Controller, ?LINE),
        ok
    end.

%% No specs between functions.

id(X) ->
    Y = X,
    Y.

swap({X, Y}) ->
    {Y, X}.
