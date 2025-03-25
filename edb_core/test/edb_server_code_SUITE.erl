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

%% Test cases
-export([test_fetch_fun_block_surrounding/1]).
-export([test_get_call_target/1]).

all() ->
    [
        test_fetch_fun_block_surrounding,
        test_get_call_target
    ].

% -----------------------------------------------------------------------------
% Test cases
% -----------------------------------------------------------------------------

test_fetch_fun_block_surrounding(Config) ->
    {ok, _, _} = edb_test_support:compile_module(Config, {filename, "test_code_inspection.erl"}, #{
        load_it => true
    }),
    {ok, Forms} = edb_server_code:fetch_abstract_forms(test_code_inspection),

    %% Auxiliary function to check that a fun block is retrieved from all its lines
    CheckIsFunBlock = fun(FirstLine, LastLine) ->
        Lines = lists:seq(FirstLine, LastLine),
        [
            ?assertEqual(
                %% Add the line number to the block, to make it easier to debug
                {line, Line, {ok, Lines}},
                {line, Line, edb_server_code:fetch_fun_block_surrounding(Line, Forms)}
            )
         || Line <- Lines
        ]
    end,

    %% go/1 (Simple case)
    CheckIsFunBlock(14, 19),

    %% cycle/2 (multiple clauses)
    CheckIsFunBlock(24, 29),

    %% just_sync/1 (arity overloading)
    CheckIsFunBlock(34, 36),

    %% just_sync/2 (arity overloading)
    CheckIsFunBlock(39, 41),

    %% make_closure/1 (ends with a non-executable line: `end.`)
    CheckIsFunBlock(46, 49),

    %% id/1 and swap/1: no specs inbetween (consecutive function forms)
    CheckIsFunBlock(54, 56),
    CheckIsFunBlock(58, 59),

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

    % Returns not_a_call when top-level expression of the line is not a call
    {error, {not_a_call, match_expr}} = edb_server_code:get_call_target(6, Forms),

    % Handles calls to MFAs
    {ok, {{foo, bar, 2}, [_, _]}} = edb_server_code:get_call_target(7, Forms),

    % Handles calls to locals
    {ok, {{call_targets, local, 0}, []}} = edb_server_code:get_call_target(8, Forms),

    % Handles calls to external fun refs
    {ok, {{foo, bar, 1}, [_]}} = edb_server_code:get_call_target(9, Forms),

    % Handles calls to local fun refs
    {ok, {{call_targets, local, 0}, []}} = edb_server_code:get_call_target(10, Forms),

    ok.
