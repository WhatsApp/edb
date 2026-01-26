-module(test_step_in).
-compile([warn_missing_spec_all]).
-compile([export_all]).

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

call_under_match() ->
    43 = foo(42).

call_under_catch() ->
    43 = catch foo(42),
    ok.

call_under_case() ->
    case foo(42) of
        _ -> ok
    end.

call_under_try() ->
    try foo(42) catch _ -> ok end.

call_under_binop() ->
    foo(42) + bar(43).

bar(Y) ->
    Y * 2.
