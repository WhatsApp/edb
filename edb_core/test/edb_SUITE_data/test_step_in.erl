-module(test_step_in).
-compile([warn_missing_spec_all]).
-export([foo/1, call_static_local/0, call_static_local_tail/0, call_static_external/0, call_static_external_tail/0]).

foo(X) ->
    X + 1.

call_static_local() ->
    foo(42),
    ok.

call_static_local_tail() ->
    foo(42).

call_static_external() ->
    ?MODULE:foo(42),
    ok.

call_static_external_tail() ->
    ?MODULE:foo(42).
