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
    ModuleSource = ~"""
        -module(call_targets).                                     %L01
        -export([fixtures/0]).                                     %L02
        -record(my_rec, {fld1 :: atom(), fld2 :: integer()}).      %L03
                                                                   %L04
        fixtures() ->                                              %L05
            Y = 42, 'not':toplevel(a, b),                          %L06
            foo:bar(13, Y), Z=43,                                  %L07
            local(),                                               %L08
            (fun foo:bar/1)(Z),                                    %L09
            (fun local/0)(),                                       %L10
            X = foo:bar(Y),                                        %L11
            X = catch local(),                                     %L12
            case foo:blah() of                                     %L13
                ok -> blah                                         %L14
            end,                                                   %L15
            case                                                   %L16
                foo:bar() of                                       %L17
                    ok -> blah                                     %L18
            end,                                                   %L19
            case X of                                              %L20
                _ -> foo:blah()                                    %L21
            end,                                                   %L22
            try X = hey:ho(42), X + 1 of                           %L23
                _ -> foo:bar()                                     %L24
            catch                                                  %L25
                _:_ -> foo:bar()                                   %L26
            end,                                                   %L27
            try X = 42, hey:ho(X) of                               %L28
                _ -> ok                                            %L29
            catch                                                  %L30
                _:_ -> ok                                          %L31
            end,                                                   %L32
            try                                                    %L33
                foo:bar(X)                                         %L34
            catch _:_ -> ok                                        %L35
            end,                                                   %L36
            begin X = foo:bar(42), X + 1 end,                      %L37
            begin X = 42, foo:bar(X + 1) end,                      %L38
            X + foo:bar(Y),                                        %L39
            hey:ho(X) + Y,                                         %L40
            hey:ho(X) + foo:bar(Y),                                %L41
            hey:ho(X) +                                            %L42
                foo:bar(Y),                                        %L43
            hey:ho(X)                                              %L44
              + foo:bar(Y),                                        %L45
            maybe ok ?= foo:bar(X) end,                            %L46
            maybe X = 42, ok = foo:bar(Y) end,                     %L47
            {hey:ho(X), foo:bar(Y)},                               %L48
            [hey:ho(X), foo:bar(Y) | pim:pam()],                   %L49
            [hey:ho(X), foo:bar(Y)],                               %L50
            #{hey:ho(X) => foo:bar(Y), blah => pim:pam()},         %L51
            #my_rec{fld1 = hey:ho(X), fld2 = foo:bar(Y)},          %L52
            ok.                                                    %
                                                                   %
        local() -> ok.                                             %
    """,
    {ok, _, _} = edb_test_support:compile_module(Config, {source, ModuleSource}, #{
        load_it => true
    }),
    {ok, Forms} = edb_server_code:fetch_abstract_forms(call_targets),

    % Returns not_found when line doesn't exit
    {error, not_found} = edb_server_code:get_call_targets(100_000, Forms),

    % Returns not_found when line has no content
    {error, not_found} = edb_server_code:get_call_targets(4, Forms),

    % Returns no_call_in_expr when top-level expression of the line is not a call
    {error, {no_call_in_expr, match_expr}} = edb_server_code:get_call_targets(6, Forms),

    % Handles calls to MFAs
    {ok, [{{foo, bar, 2}, [_, _]}]} = edb_server_code:get_call_targets(7, Forms),

    % Handles calls to locals
    {ok, [{{call_targets, local, 0}, []}]} = edb_server_code:get_call_targets(8, Forms),

    % Handles calls to external fun refs
    {ok, [{{foo, bar, 1}, [_]}]} = edb_server_code:get_call_targets(9, Forms),

    % Handles calls to local fun refs
    {ok, [{{call_targets, local, 0}, []}]} = edb_server_code:get_call_targets(10, Forms),

    % Handles calls as LHS of a match
    {ok, [{{foo, bar, 1}, [_]}]} = edb_server_code:get_call_targets(11, Forms),

    % Handles calls under a catch statement
    {ok, [{{call_targets, local, 0}, []}]} = edb_server_code:get_call_targets(12, Forms),

    % Handles calls in a case statement
    {ok, [{{foo, blah, 0}, []}]} = edb_server_code:get_call_targets(13, Forms),

    % Doesn't pick calls in a case when the expression is on a different line
    {error, {no_call_in_expr, case_expr}} = edb_server_code:get_call_targets(16, Forms),

    % Doesn't pick calls in branches of a case statement
    {error, {no_call_in_expr, case_expr}} = edb_server_code:get_call_targets(20, Forms),

    % Handles calls in a try statement
    {ok, [{{hey, ho, 1}, [_]}]} = edb_server_code:get_call_targets(23, Forms),

    % Only considers the first statement in a try-statement
    {error, {no_call_in_expr, try_expr}} = edb_server_code:get_call_targets(28, Forms),

    % Doesn't pick calls in a try when the call is on a different line
    {error, {no_call_in_expr, try_expr}} = edb_server_code:get_call_targets(33, Forms),

    % Handles calls in a block
    {ok, [{{foo, bar, 1}, [_]}]} = edb_server_code:get_call_targets(37, Forms),

    % Only considers the first statement in a block
    {error, {no_call_in_expr, block_expr}} = edb_server_code:get_call_targets(38, Forms),

    % Can step-into either LHS and RHS of a binop, non-deterministically if they are on the same line
    {ok, [{{foo, bar, 1}, [_]}]} = edb_server_code:get_call_targets(39, Forms),
    {ok, [{{hey, ho, 1}, [_]}]} = edb_server_code:get_call_targets(40, Forms),
    {ok, [{{foo, bar, 1}, [_]}, {{hey, ho, 1}, [_]}]} = edb_server_code:get_call_targets(41, Forms),
    {ok, [{{hey, ho, 1}, [_]}]} = edb_server_code:get_call_targets(42, Forms),
    {ok, [{{foo, bar, 1}, [_]}]} = edb_server_code:get_call_targets(45, Forms),

    % Can step-into calls inside maybes
    {ok, [{{foo, bar, 1}, [_]}]} = edb_server_code:get_call_targets(46, Forms),
    {error, {no_call_in_expr, maybe_expr}} = edb_server_code:get_call_targets(47, Forms),

    % Can step into calls in a tuple
    {ok, [{{foo, bar, 1}, [_]}, {{hey, ho, 1}, [_]}]} = edb_server_code:get_call_targets(48, Forms),

    % Can step into calls in a list
    {ok, [{{foo, bar, 1}, [_]}, {{hey, ho, 1}, [_]}, {{pim, pam, 0}, []}]} = edb_server_code:get_call_targets(
        49, Forms
    ),
    {ok, [{{foo, bar, 1}, [_]}, {{hey, ho, 1}, [_]}]} = edb_server_code:get_call_targets(50, Forms),

    % Can step into calls in a map
    {ok, [{{pim, pam, 0}, []}, {{foo, bar, 1}, [_]}, {{hey, ho, 1}, [_]}]} = edb_server_code:get_call_targets(
        51, Forms
    ),

    % Can step into calls in a record
    {ok, [{{foo, bar, 1}, [_]}, {{hey, ho, 1}, [_]}]} = edb_server_code:get_call_targets(52, Forms),

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
