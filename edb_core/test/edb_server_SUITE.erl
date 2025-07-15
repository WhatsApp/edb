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
-module(edb_server_SUITE).

%% erlfmt:ignore
% @fb-only
-typing([eqwalizer]).

% @fb-only
-include_lib("stdlib/include/assert.hrl").
-include_lib("common_test/include/ct.hrl").

%% CT callbacks
-export([all/0, suite/0]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Test cases
-export([
    test_reapply_breakpoints_reapplies_breakpoints/1,
    test_reapply_breakpoints_does_not_reapply_any_breakpoints_if_the_reloaded_module_does_not_support_breakpoints_on_a_line/1
]).

suite() -> [].

all() ->
    [
        test_reapply_breakpoints_reapplies_breakpoints,
        test_reapply_breakpoints_does_not_reapply_any_breakpoints_if_the_reloaded_module_does_not_support_breakpoints_on_a_line
    ].

init_per_testcase(_TestCase, Config) ->
    Config1 = start_debugger_node(Config),
    Config1.

end_per_testcase(_TestCase, _Config) ->
    edb_test_support:stop_all_peers(),
    ok.

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------
test_reapply_breakpoints_reapplies_breakpoints(Config) ->
    % Create first version of test module
    ModuleSource1 =
        "-module(test_reapply_module).   %L01\n"
        "-export([test_function/1]).     %L02\n"
        "test_function(Parent) ->        %L03\n"
        "    A = ok,                     %L04\n"
        "    B = A,                      %L05\n"
        "    B,                          %L06\n"
        "    Parent ! done_mod_1.        %L07\n",

    % Create slightly modified version of the test module
    ModuleSource2 =
        "-module(test_reapply_module).   %L01\n"
        "-export([test_function/1]).     %L02\n"
        "test_function(Parent) ->        %L03\n"
        "    A = ok,                     %L04\n"
        "    C = A,                      %L05\n"
        "    C,                          %L06\n"
        "    Parent ! done_mod_2.        %L07\n",

    on_debugger_node(Config, fun() ->
        % Start peer node with the test module
        {ok, #{node := Node, modules := #{test_reapply_module := _}, peer := Peer, cookie := Cookie}} = edb_test_support:start_peer_node(
            Config, #{
                enable_debugging_mode => true,
                modules => [{source, ModuleSource1}]
            }
        ),

        ok = edb:attach(#{node => Node, cookie => Cookie}),

        % Set breakpoints on lines 4 and 5
        ok = edb:add_breakpoint(test_reapply_module, 4),
        ok = edb:add_breakpoint(test_reapply_module, 5),

        % Sanity-check: Verify breakpoints are set
        Breakpoints1 = edb:get_breakpoints(test_reapply_module),
        ?assertEqual(
            [
                #{line => 4, module => test_reapply_module},
                #{line => 5, module => test_reapply_module}
            ],
            Breakpoints1
        ),

        {ok, test_reapply_module, _SourceFilePath} = peer:call(Peer, edb_test_support, compile_module, [
            Config, {source, ModuleSource2}, #{load_it => true}
        ]),

        % Sanity-check: edb_server still recognises the breakpoints after reloading
        Breakpoints2 = edb:get_breakpoints(test_reapply_module),
        ?assertEqual(
            [
                #{line => 4, module => test_reapply_module},
                #{line => 5, module => test_reapply_module}
            ],
            Breakpoints2
        ),

        % Call test_reapply_module:test_function to verify that no breakpoints are actually hit
        Receiver = self(),
        _TestPid = erlang:spawn(fun() ->
            peer:call(Peer, test_reapply_module, test_function, [Receiver])
        end),

        % Receive 'done_mod_2' indicating end of function reached
        receive
            done_mod_2 -> ok
        after 5000 ->
            error(timeout_waiting_for_test_process)
        end,

        % Reapply breakpoints
        ok = peer:call(Peer, edb_server, reapply_breakpoints, [test_reapply_module]),

        % Sanity-check: edb_server still recognises the breakpoints after reapplying
        Breakpoints3 = edb:get_breakpoints(test_reapply_module),
        ?assertEqual(
            [
                #{line => 4, module => test_reapply_module},
                #{line => 5, module => test_reapply_module}
            ],
            Breakpoints3
        ),

        % Call test_reapply_module:test_function to verify that both breakpoints get hit
        _TestPid2 = erlang:spawn(fun() ->
            peer:call(Peer, test_reapply_module, test_function, [Receiver])
        end),

        % Wait for the test process to hit the breakpoint
        {ok, paused} = edb:wait(),

        % Breakpoint on line 4 is hit
        Breakpoints4Map = edb:get_breakpoints_hit(),
        Breakpoints4 = maps:values(Breakpoints4Map),
        ?assertEqual(
            [#{line => 4, module => test_reapply_module}], Breakpoints4
        ),

        % Resume the test process and wait to hit the next breakpoint
        {ok, resumed} = edb:continue(),
        {ok, paused} = edb:wait(),

        Breakpoints5Map = edb:get_breakpoints_hit(),
        % Breakpoint on line 4 is hit
        Breakpoints5 = maps:values(Breakpoints5Map),
        ?assertEqual(
            [#{line => 5, module => test_reapply_module}], Breakpoints5
        ),
        ok
    end),
    ok.

test_reapply_breakpoints_does_not_reapply_any_breakpoints_if_the_reloaded_module_does_not_support_breakpoints_on_a_line(
    Config
) ->
    % Create first version of test module
    ModuleSource1 =
        "-module(test_reapply_module).   %L01\n"
        "-export([test_function/1]).     %L02\n"
        "test_function(Parent) ->        %L03\n"
        "    A = ok,                     %L04\n"
        "    B = A,                      %L05\n"
        "    B,                          %L06\n"
        "    Parent ! done_mod_1.        %L07\n",

    % Create slightly modified version of the test module
    ModuleSource2 =
        "-module(test_reapply_module).   %L01\n"
        "-export([test_function/1]).     %L02\n"
        "test_function(Parent) ->        %L03\n"
        "    A = ok,                     %L04\n"
        "                                %L05\n"
        "    C = A,                      %L06\n"
        "    C,                          %L07\n"
        "    Parent ! done_mod_2.        %L08\n",

    on_debugger_node(Config, fun() ->
        % Start peer node with the test module
        {ok, #{node := Node, modules := #{test_reapply_module := _}, peer := Peer, cookie := Cookie}} = edb_test_support:start_peer_node(
            Config, #{
                enable_debugging_mode => true,
                modules => [{source, ModuleSource1}]
            }
        ),

        ok = edb:attach(#{node => Node, cookie => Cookie}),

        % Set breakpoints on lines 4 and 5
        ok = edb:add_breakpoint(test_reapply_module, 4),
        ok = edb:add_breakpoint(test_reapply_module, 5),

        % Sanity-check: Verify breakpoints are set
        Breakpoints1 = edb:get_breakpoints(test_reapply_module),
        ?assertEqual(
            [
                #{line => 4, module => test_reapply_module},
                #{line => 5, module => test_reapply_module}
            ],
            Breakpoints1
        ),

        {ok, test_reapply_module, _SourceFilePath} = peer:call(Peer, edb_test_support, compile_module, [
            Config, {source, ModuleSource2}, #{load_it => true}
        ]),

        % Sanity-check: edb_server still recognises the breakpoints after reloading
        Breakpoints2 = edb:get_breakpoints(test_reapply_module),
        ?assertEqual(
            [
                #{line => 4, module => test_reapply_module},
                #{line => 5, module => test_reapply_module}
            ],
            Breakpoints2
        ),

        % Call test_reapply_module:test_function to verify that no breakpoints are actually hit
        Receiver = self(),
        _TestPid = erlang:spawn(fun() ->
            peer:call(Peer, test_reapply_module, test_function, [Receiver])
        end),

        % Receive 'done' indicating end of function reached
        receive
            done_mod_2 -> ok
        after 5000 ->
            error(timeout_waiting_for_test_process)
        end,

        % Reapply breakpoints call fails because the reloaded module does not support breakpoints on line 5
        ?assertEqual({error, {badkey, 5}}, peer:call(Peer, edb_server, reapply_breakpoints, [test_reapply_module])),

        % Sanity-check: edb_server still recognises the breakpoints after reapplying
        Breakpoints3 = edb:get_breakpoints(test_reapply_module),
        ?assertEqual(
            [
                #{line => 4, module => test_reapply_module},
                #{line => 5, module => test_reapply_module}
            ],
            Breakpoints3
        ),

        % Call test_reapply_module:test_function to verify that no breakpoints get hit
        _TestPid2 = erlang:spawn(fun() ->
            peer:call(Peer, test_reapply_module, test_function, [Receiver])
        end),

        % Receive 'done' indicating end of function reached
        receive
            done_mod_2 -> ok
        after 5000 ->
            error(timeout_waiting_for_test_process)
        end,

        ok
    end),
    ok.

% %%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------
-spec start_debugger_node(Config) -> Config when
    Config :: ct_suite:ct_config().
%% erlfmt:ignore
start_debugger_node(Config0) ->
    {ok, #{peer := Peer}} = edb_test_support:start_peer_no_dist(Config0, #{
        copy_code_path => true
    }),
    Config1 = [{debugger_peer_key(), Peer} | Config0],
    {ok, _} = on_debugger_node(Config1, fun() ->
        % @fb-only
    end),
    Config1.

-spec on_debugger_node(Config, fun(() -> Result)) -> Result when
    Config :: ct_suite:ct_config().
on_debugger_node(Config, Fun) ->
    Peer = ?config(debugger_peer_key(), Config),
    peer:call(Peer, erlang, apply, [Fun, []]).

-spec debugger_peer_key() -> debugger_peer.
debugger_peer_key() -> debugger_peer.
