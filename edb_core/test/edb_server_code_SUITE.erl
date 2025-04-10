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
-module(edb_server_code_SUITE).

%% erlfmt:ignore
% @fb-only
-typing([eqwalizer]).

% @fb-only
-include_lib("stdlib/include/assert.hrl").

%% CT callbacks
-export([all/0]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Test cases
-export([test_find_fun/1]).
-export([test_find_fun_containing_line/1]).
-export([test_get_line_span/1]).
-export([test_get_call_target/1]).

all() ->
    [
        test_find_fun,
        test_find_fun_containing_line,
        test_get_line_span,
        test_get_call_target
    ].

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    code:purge(test_code_inspection),
    code:delete(test_code_inspection),
    code:purge(test_code_inspection).

% -----------------------------------------------------------------------------
% Test cases
% -----------------------------------------------------------------------------

test_find_fun(Config) ->
    {ok, _, _} = edb_test_support:compile_module(Config, {filename, "test_code_inspection.erl"}, #{
        load_it => true
    }),
    {ok, Forms} = edb_server_code:fetch_abstract_forms(test_code_inspection),

    CheckFinds = fun(FA = {Name, Arity}) ->
        Res = edb_server_code:find_fun(Name, Arity, Forms),
        ?assertMatch({ok, _}, Res, FA),
        {ok, Actual} = Res,
        check_function_form_is(FA, Actual, FA)
    end,

    CheckFinds({sync, 2}),
    CheckFinds({cycle, 2}),
    CheckFinds({just_sync, 1}),
    CheckFinds({make_closure, 1}),
    CheckFinds({id, 1}),
    CheckFinds({swap, 1}),
    ok.

test_find_fun_containing_line(Config) ->
    {ok, _, _} = edb_test_support:compile_module(Config, {filename, "test_code_inspection.erl"}, #{
        load_it => true
    }),
    {ok, Forms} = edb_server_code:fetch_abstract_forms(test_code_inspection),

    check_finds_fun_containing_Line(Forms, {go, 1}, 14),
    check_finds_fun_containing_Line(Forms, {cycle, 2}, 24),
    check_finds_fun_containing_Line(Forms, {just_sync, 1}, 34),
    check_finds_fun_containing_Line(Forms, {just_sync, 2}, 39),
    check_finds_fun_containing_Line(Forms, {make_closure, 1}, 46),
    check_finds_fun_containing_Line(Forms, {id, 1}, 54),
    check_finds_fun_containing_Line(Forms, {swap, 1}, 58),
    ok.

test_get_line_span(Config) ->
    {ok, _, _} = edb_test_support:compile_module(Config, {filename, "test_code_inspection.erl"}, #{
        load_it => true
    }),
    {ok, Forms} = edb_server_code:fetch_abstract_forms(test_code_inspection),

    CheckIsFunBlock = fun({Name, Arity}, FirstLine, LastLine) ->
        Res = edb_server_code:find_fun_containing_line(FirstLine, Forms),
        ?assertMatch({ok, _}, Res, {FirstLine, LastLine}),
        {ok, Form} = Res,

        Span = edb_server_code:get_line_span(Form),
        ?assertEqual(
            {FirstLine, LastLine},
            Span
        ),

        Lines = lists:seq(FirstLine, LastLine),
        [check_finds_fun_containing_Line(Forms, {Name, Arity}, Line) || Line <- Lines]
    end,

    %% go/1 (Simple case)
    CheckIsFunBlock({go, 1}, 14, 19),

    %% cycle/2 (multiple clauses)
    CheckIsFunBlock({cycle, 2}, 24, 29),

    %% just_sync/1 (arity overloading)
    CheckIsFunBlock({just_sync, 1}, 34, 36),

    %% just_sync/2 (arity overloading)
    CheckIsFunBlock({just_sync, 2}, 39, 41),

    %% make_closure/1 (ends with a non-executable line: `end.`)
    CheckIsFunBlock({make_closure, 1}, 46, 49),

    %% id/1 and swap/1: no specs inbetween (consecutive function forms)
    CheckIsFunBlock({id, 1}, 54, 56),
    CheckIsFunBlock({swap, 1}, 58, 59),

    ok.

test_get_call_target(Config) ->
    ModuleSource = [
        ~"-module(call_targets).                                     %L01\n",
        ~"                                                           %L02\n",
        ~"-export([fixtures/0]).                                     %L03\n",
        ~"                                                           %L04\n",
        ~"fixtures() ->                                              %L05\n",
        ~"    Y = 42, 'not':toplevel(a, b),                          %L06\n",
        ~"    foo:bar(13, Y), Z=43,                                  %L07\n",
        ~"    local(),                                               %L08\n",
        ~"    (fun foo:bar/1)(Z),                                    %L09\n",
        ~"    (fun local/0)(),                                       %L10\n",
        ~"    X = foo:bar(Y),                                        %L11\n",
        ~"    X = catch local(),                                     %L12\n",
        ~"    case foo:blah() of                                     %L13\n",
        ~"        ok -> blah                                         %L14\n",
        ~"    end,                                                   %L15\n",
        ~"    case X of                                              %L16\n",
        ~"        _ -> foo:blah()                                    %L17\n",
        ~"    end,                                                   %L18\n",
        ~"    ok.                                                    %\n",
        ~"                                                           %\n",
        ~"local() -> ok.                                             %\n"
    ],
    {ok, _, _} = edb_test_support:compile_module(Config, {source, ModuleSource}, #{
        load_it => true
    }),
    {ok, Forms} = edb_server_code:fetch_abstract_forms(call_targets),

    % Returns not_found when line doesn't exit
    {error, not_found} = edb_server_code:get_call_target(100_000, Forms),

    % Returns not_found when line has no content
    {error, not_found} = edb_server_code:get_call_target(2, Forms),

    % Returns no_call_in_expr when top-level expression of the line is not a call
    {error, {no_call_in_expr, match_expr}} = edb_server_code:get_call_target(6, Forms),

    % Handles calls to MFAs
    {ok, {{foo, bar, 2}, [_, _]}} = edb_server_code:get_call_target(7, Forms),

    % Handles calls to locals
    {ok, {{call_targets, local, 0}, []}} = edb_server_code:get_call_target(8, Forms),

    % Handles calls to external fun refs
    {ok, {{foo, bar, 1}, [_]}} = edb_server_code:get_call_target(9, Forms),

    % Handles calls to local fun refs
    {ok, {{call_targets, local, 0}, []}} = edb_server_code:get_call_target(10, Forms),

    % Handles calls as LHS of a match
    {ok, {{foo, bar, 1}, [_]}} = edb_server_code:get_call_target(11, Forms),

    % Handles calls under a catch statement
    {ok, {{call_targets, local, 0}, []}} = edb_server_code:get_call_target(12, Forms),

    % Handles calls in a case statement
    {ok, {{foo, blah, 0}, []}} = edb_server_code:get_call_target(13, Forms),

    % Doesn't pick calls in branches of a case statement
    {error, {no_call_in_expr, case_expr}} = edb_server_code:get_call_target(16, Forms),

    ok.

% -----------------------------------------------------------------------------
% Helpers
% -----------------------------------------------------------------------------
-spec check_finds_fun_containing_Line(Forms, {Name, Arity}, Line) -> ok when
    Forms :: edb_server_code:forms(),
    Name :: atom(),
    Arity :: arity(),
    Line :: pos_integer().
check_finds_fun_containing_Line(Forms, {Name, Arity}, Line) ->
    Res = edb_server_code:find_fun_containing_line(Line, Forms),

    ?assertMatch({ok, _}, Res, {line, Line}),
    {ok, Form} = Res,

    check_function_form_is({Name, Arity}, Form, {line, Line}),
    ok.

-spec check_function_form_is({Name, Arity}, Form, Descr) -> ok when
    Name :: atom(),
    Arity :: arity(),
    Form :: edb_server_code:form(),
    Descr :: term().
check_function_form_is({Name, Arity}, Form, Descr) ->
    ?assertEqual(function, erl_syntax:type(Form), Descr),
    ?assertEqual(
        {Name, Arity},
        {erl_syntax:atom_value(erl_syntax:function_name(Form)), erl_syntax:function_arity(Form)},
        Descr
    ),
    ok.
