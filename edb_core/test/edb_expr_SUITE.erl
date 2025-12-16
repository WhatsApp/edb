%% Copyright (c) Meta Platforms, Inc. and affiliates.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%% % @format
%%
-module(edb_expr_SUITE).

%% erlfmt:ignore
% @fb-only: -oncall("whatsapp_server_devx").
-typing([eqwalizer]).

-include_lib("assert/include/assert.hrl").

%% CT callbacks
-export([all/0, groups/0]).

%% compile_expr test cases
-export([test_compile_expr_evaluates/1]).
-export([test_compile_expr_ignores_vars_when_no_free_vars_are_given/1]).
-export([test_compile_expr_fails_to_eval_if_value_is_too_large/1]).
-export([test_compile_expr_uses_given_location_on_exceptions/1]).
-export([test_compile_expr_reports_parsing_errors_using_given_location/1]).
-export([test_compile_expr_reports_compilation_errors_using_given_location/1]).
-export([test_compile_expr_accepts_trailing_dot/1]).

%% compile_expr test cases
-export([test_compile_guard_evaluates/1]).
-export([test_compile_guard_fails_to_eval_if_value_is_too_large/1]).
-export([test_compile_guard_reports_illegal_guard_in_right_position/1]).
-export([test_compile_guard_reports_parsing_errors_using_given_location/1]).
-export([test_compile_guard_reports_compilation_errors_using_given_location/1]).

all() ->
    [
        {group, compile_expr},
        {group, compile_guard}
    ].

groups() ->
    [
        {compile_expr, [
            test_compile_expr_evaluates,
            test_compile_expr_ignores_vars_when_no_free_vars_are_given,
            test_compile_expr_fails_to_eval_if_value_is_too_large,
            test_compile_expr_uses_given_location_on_exceptions,
            test_compile_expr_reports_parsing_errors_using_given_location,
            test_compile_expr_reports_compilation_errors_using_given_location,
            test_compile_expr_accepts_trailing_dot
        ]},
        {compile_guard, [
            test_compile_guard_evaluates,
            test_compile_guard_fails_to_eval_if_value_is_too_large,
            test_compile_guard_reports_illegal_guard_in_right_position,
            test_compile_guard_reports_parsing_errors_using_given_location,
            test_compile_guard_reports_compilation_errors_using_given_location
        ]}
    ].

%% compile_expr test cases
test_compile_expr_evaluates(_Config) ->
    {ok, Expr} = edb_expr:compile_expr(~"X * Y + 1", #{free_vars => [~"X", ~"Y", ~"Z"]}),
    Eval = edb_expr:entrypoint(Expr),

    ?assertEqual(42 * 2 + 1, Eval(#{vars => #{~"X" => {value, 42}, ~"Y" => {value, 2}, ~"Z" => {value, 1000}}})),
    ?assertEqual(15 * 7 + 1, Eval(#{vars => #{~"X" => {value, 15}, ~"Y" => {value, 7}, ~"Z" => {value, 1000}}})),
    ok.

test_compile_expr_ignores_vars_when_no_free_vars_are_given(_Config) ->
    {ok, Expr} = edb_expr:compile_expr(~"40 + 2", #{free_vars => []}),
    Eval = edb_expr:entrypoint(Expr),

    ?assertEqual(42, Eval(#{vars => #{}}), "Works if vars is given and an empty map"),
    ?assertEqual(42, Eval(#{}), "Works if vars is not provided"),
    ok.

test_compile_expr_fails_to_eval_if_value_is_too_large(_Config) ->
    {ok, Expr} = edb_expr:compile_expr(~"X * Y + 1", #{free_vars => [~"X", ~"Y", ~"Z"]}),
    Eval = edb_expr:entrypoint(Expr),

    try Eval(#{vars => #{~"X" => {too_large, 1000, 500}, ~"Y" => {value, 2}, ~"Z" => {too_large, 2000, 500}}}) of
        _ -> throw("Expected eval to fail!")
    catch
        error:Reason:ST ->
            ?assertEqual(
                {unavailable_values, #{~"X" => {too_large, 1000, 500}}},
                Reason
            ),
            ?assertEqual([], ST, "We don't leak implementation details to the caller")
    end,
    ok.

test_compile_expr_uses_given_location_on_exceptions(_Config) ->
    ExprLine = 1080,
    {ok, Expr} = edb_expr:compile_expr(~"R = X * Y + 1, throw({bam, R})", #{
        free_vars => [~"X", ~"Y"],
        start_line => ExprLine,
        start_col => 4
    }),
    Eval = edb_expr:entrypoint(Expr),

    try Eval(#{vars => #{~"X" => {value, 42}, ~"Y" => {value, 2}}}) of
        _ -> throw("Expected eval to fail!")
    catch
        throw:Reason:ST ->
            % Sanity check: expected exception is thrown
            ?assertEqual({bam, 85}, Reason),

            ?assertMatch(
                [{_, _, _, [{file, _}, {line, ExprLine}]} | _],
                ST
            )
    end,
    ok.

test_compile_expr_reports_parsing_errors_using_given_location(_Config) ->
    ExprLine = 1080,
    ExprCol = 214,
    {error, CompileError} = edb_expr:compile_expr(~"X * Y 1", #{
        free_vars => [~"X", ~"Y"],
        start_line => ExprLine,
        start_col => ExprCol
    }),

    ?assertEqual(
        {{ExprLine, ExprCol + 6}, erl_parse, ["syntax error before: ", "1"]},
        CompileError
    ),
    ok.

test_compile_expr_reports_compilation_errors_using_given_location(_Config) ->
    ExprLine = 1080,
    ExprCol = 214,
    {error, CompileError} = edb_expr:compile_expr(~"X * Y + W", #{
        free_vars => [~"X", ~"Y"],
        start_line => ExprLine,
        start_col => ExprCol
    }),

    ?assertEqual(
        {{ExprLine, ExprCol + 8}, erl_lint, {unbound_var, 'W'}},
        CompileError
    ),
    ok.

test_compile_expr_accepts_trailing_dot(_Config) ->
    {ok, Expr} = edb_expr:compile_expr(~"X * Y + 1.", #{free_vars => [~"X", ~"Y", ~"Z"]}),
    Eval = edb_expr:entrypoint(Expr),

    ?assertEqual(42 * 2 + 1, Eval(#{vars => #{~"X" => {value, 42}, ~"Y" => {value, 2}, ~"Z" => {value, 1000}}})),
    ok.

%$ compile_guard test cases
test_compile_guard_evaluates(_Config) ->
    {ok, Expr} = edb_expr:compile_guard(~"is_list(X); Y > 42", #{free_vars => [~"X", ~"Y", ~"Z"]}),
    Eval = edb_expr:entrypoint(Expr),

    ?assert(Eval(#{vars => #{~"X" => {value, [foo]}, ~"Y" => {value, 41}, ~"Z" => {value, 1000}}})),
    ?assert(Eval(#{vars => #{~"X" => {value, blah}, ~"Y" => {value, 43}, ~"Z" => {value, 1000}}})),
    ?assertNot(Eval(#{vars => #{~"X" => {value, blah}, ~"Y" => {value, 40}, ~"Z" => {value, 1000}}})),
    ok.

test_compile_guard_fails_to_eval_if_value_is_too_large(_Config) ->
    {ok, Expr} = edb_expr:compile_guard(~"is_list(X); Y > 42", #{free_vars => [~"X", ~"Y", ~"Z"]}),
    Eval = edb_expr:entrypoint(Expr),

    try Eval(#{vars => #{~"X" => {too_large, 1000, 500}, ~"Y" => {value, 2}, ~"Z" => {too_large, 2000, 500}}}) of
        _ -> throw("Expected eval to fail!")
    catch
        error:Reason:ST ->
            ?assertEqual(
                {unavailable_values, #{~"X" => {too_large, 1000, 500}}},
                Reason
            ),
            ?assertEqual([], ST, "We don't leak implementation details to the caller")
    end,
    ok.

test_compile_guard_reports_illegal_guard_in_right_position(_Config) ->
    ExprLine = 1080,
    ExprCol = 3050,
    {error, Reason} = edb_expr:compile_guard(~"throw({bam, X})", #{
        free_vars => [~"X"],
        start_line => ExprLine,
        start_col => ExprCol
    }),
    ?assertEqual(
        {{ExprLine, ExprCol}, erl_lint, illegal_guard_expr},
        Reason
    ),

    ok.

test_compile_guard_reports_parsing_errors_using_given_location(_Config) ->
    ExprLine = 1080,
    ExprCol = 214,
    {error, CompileError} = edb_expr:compile_guard(~"X > Y 1", #{
        free_vars => [~"X", ~"Y"],
        start_line => ExprLine,
        start_col => ExprCol
    }),

    ?assertEqual(
        {{ExprLine, ExprCol + 6}, erl_parse, ["syntax error before: ", "1"]},
        CompileError
    ),
    ok.

test_compile_guard_reports_compilation_errors_using_given_location(_Config) ->
    ExprLine = 1080,
    ExprCol = 214,
    {error, CompileError} = edb_expr:compile_guard(~"X > Y andalso W", #{
        free_vars => [~"X", ~"Y"],
        start_line => ExprLine,
        start_col => ExprCol
    }),

    ?assertEqual(
        {{ExprLine, ExprCol + 14}, erl_lint, {unbound_var, 'W'}},
        CompileError
    ),
    ok.
