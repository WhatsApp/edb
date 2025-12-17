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
% @fb-only: -oncall("whatsapp_server_devx").

-include_lib("assert/include/assert.hrl").
-include_lib("common_test/include/ct.hrl").

%% CT callbacks
-export([all/0, groups/0, suite/0]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Test cases for the reapply_breakpoints group
-export([test_reapply_breakpoints_reapplies_breakpoints/1]).
-export([test_reapply_breakpoints_reapplies_function_breakpoints/1]).
-export([
    test_reapply_breakpoints_does_not_reapply_any_breakpoints_if_the_reloaded_module_does_not_support_breakpoints_on_a_line/1
]).

%% Test cases for the substitute_line_breakpoints group
-export([test_add_module_substitute_transfers_existing_breakpoints_to_substitute_module/1]).
-export([test_add_module_substitute_adds_new_breakpoints_to_substitute_module/1]).
-export([test_remove_module_substitute_transfers_breakpoints_back_to_original_module/1]).
-export([test_error_if_substitute_already_has_breakpoints_set/1]).

%% Test cases for the substitute_function_breakpoints group
-export([test_add_module_substitute_transfers_existing_function_breakpoints_to_substitute_module/1]).
-export([test_add_module_substitute_adds_new_function_breakpoints_to_substitute_module/1]).
-export([test_remove_module_substitute_transfers_function_breakpoints_back_to_original_module/1]).

%% Test cases for the substitute_stepping group
-export([test_add_module_substitute_transfers_stepping_breakpoints/1]).
-export([test_additional_frames_are_added_in_step_patterns/1]).
-export([test_stepping_breakpoints_work_after_removing_substitute/1]).

%% Test cases for the substitute_reporting group
-export([test_original_module_is_reported_in_stack_frames/1]).
-export([test_original_module_is_reported_in_paused_event_for_line_breakpoint/1]).
-export([test_original_module_is_reported_in_paused_event_for_function_breakpoint/1]).

%% Test cases for the substitute_multiplicity group
-export([test_add_module_substitute_handles_transitive_substitutes/1]).
-export([test_remove_module_substitute_handles_transitive_substitutes/1]).
-export([test_error_if_module_already_has_a_substitute/1]).
-export([test_error_if_substitute_is_already_a_substitute/1]).
-export([test_error_if_try_removing_intermediate_substitute/1]).
-export([test_error_if_try_removing_non_existent_substitute/1]).

%% erlfmt:ignore
suite() -> [
    % @fb-only: {appatic, #{enable_autoclean => true}}
].

groups() ->
    [
        {reapply_breakpoints, [
            test_reapply_breakpoints_reapplies_breakpoints,
            test_reapply_breakpoints_reapplies_function_breakpoints,
            test_reapply_breakpoints_does_not_reapply_any_breakpoints_if_the_reloaded_module_does_not_support_breakpoints_on_a_line
        ]},
        {substitute_line_breakpoints, [
            test_add_module_substitute_transfers_existing_breakpoints_to_substitute_module,
            test_add_module_substitute_adds_new_breakpoints_to_substitute_module,
            test_remove_module_substitute_transfers_breakpoints_back_to_original_module,
            test_error_if_substitute_already_has_breakpoints_set
        ]},
        {substitute_function_breakpoints, [
            test_add_module_substitute_transfers_existing_function_breakpoints_to_substitute_module,
            test_add_module_substitute_adds_new_function_breakpoints_to_substitute_module,
            test_remove_module_substitute_transfers_function_breakpoints_back_to_original_module
        ]},
        {substitute_stepping, [
            test_add_module_substitute_transfers_stepping_breakpoints,
            test_additional_frames_are_added_in_step_patterns,
            test_stepping_breakpoints_work_after_removing_substitute
        ]},
        {substitute_reporting, [
            test_original_module_is_reported_in_stack_frames,
            test_original_module_is_reported_in_paused_event_for_line_breakpoint,
            test_original_module_is_reported_in_paused_event_for_function_breakpoint
        ]},
        {substitute_multiplicity, [
            test_add_module_substitute_handles_transitive_substitutes,
            test_remove_module_substitute_handles_transitive_substitutes,
            test_error_if_module_already_has_a_substitute,
            test_error_if_substitute_is_already_a_substitute,
            test_error_if_try_removing_intermediate_substitute,
            test_error_if_try_removing_non_existent_substitute
        ]}
    ].

all() ->
    [
        {group, reapply_breakpoints},
        {group, substitute_line_breakpoints},
        {group, substitute_function_breakpoints},
        {group, substitute_stepping},
        {group, substitute_multiplicity},
        {group, substitute_reporting}
    ].

init_per_testcase(_TestCase, Config) ->
    Config1 = edb_test_support:start_debugger_node(Config),
    Config1.

end_per_testcase(_TestCase, _Config) ->
    edb_test_support:stop_all_peers(),
    ok.

% ------------------------------------------------------------------
% Test cases for the reapply_breakpoints group
% ------------------------------------------------------------------

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

    edb_test_support:on_debugger_node(Config, fun() ->
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
                #{type => line, line => 4, module => test_reapply_module},
                #{type => line, line => 5, module => test_reapply_module}
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
                #{type => line, line => 4, module => test_reapply_module},
                #{type => line, line => 5, module => test_reapply_module}
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
                #{type => line, line => 4, module => test_reapply_module},
                #{type => line, line => 5, module => test_reapply_module}
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
            [#{type => line, line => 4, module => test_reapply_module}], Breakpoints4
        ),

        % Resume the test process and wait to hit the next breakpoint
        {ok, resumed} = edb:continue(),
        {ok, paused} = edb:wait(),

        Breakpoints5Map = edb:get_breakpoints_hit(),
        % Breakpoint on line 4 is hit
        Breakpoints5 = maps:values(Breakpoints5Map),
        ?assertEqual(
            [#{type => line, line => 5, module => test_reapply_module}], Breakpoints5
        ),
        ok
    end),
    ok.

test_reapply_breakpoints_reapplies_function_breakpoints(Config) ->
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

    edb_test_support:on_debugger_node(Config, fun() ->
        % Start peer node with the test module
        {ok, #{node := Node, modules := #{test_reapply_module := _}, peer := Peer, cookie := Cookie}} = edb_test_support:start_peer_node(
            Config, #{
                enable_debugging_mode => true,
                modules => [{source, ModuleSource1}],
                compile_flags => [debug_info, beam_debug_info]
            }
        ),

        ok = edb:attach(#{node => Node, cookie => Cookie}),

        % Set function breakpoint on test_function/1
        ok = edb:add_function_breakpoint(test_reapply_module, test_function, 1),

        % Sanity-check: Verify function breakpoint is set
        Breakpoints1 = edb:get_breakpoints(test_reapply_module),
        ?assertEqual(
            [
                #{type => function, module => test_reapply_module, function => {test_reapply_module, test_function, 1}}
            ],
            Breakpoints1
        ),

        {ok, test_reapply_module, _SourceFilePath} = peer:call(Peer, edb_test_support, compile_module, [
            Config, {source, ModuleSource2}, #{load_it => true, flags => [debug_info, beam_debug_info]}
        ]),

        % Sanity-check: edb_server still recognises the function breakpoint after reloading
        Breakpoints2 = edb:get_breakpoints(test_reapply_module),
        ?assertEqual(
            [
                #{type => function, module => test_reapply_module, function => {test_reapply_module, test_function, 1}}
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

        % Sanity-check: edb_server still recognises the function breakpoint after reapplying
        Breakpoints3 = edb:get_breakpoints(test_reapply_module),
        ?assertEqual(
            [
                #{type => function, module => test_reapply_module, function => {test_reapply_module, test_function, 1}}
            ],
            Breakpoints3
        ),

        % Call test_reapply_module:test_function to verify that the function breakpoint gets hit
        _TestPid2 = erlang:spawn(fun() ->
            peer:call(Peer, test_reapply_module, test_function, [Receiver])
        end),

        % Wait for the test process to hit the breakpoint
        {ok, paused} = edb:wait(),

        % Function breakpoint is hit
        Breakpoints4Map = edb:get_breakpoints_hit(),
        Breakpoints4 = maps:values(Breakpoints4Map),
        ?assertEqual(
            [#{type => function, module => test_reapply_module, function => {test_reapply_module, test_function, 1}}],
            Breakpoints4
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

    edb_test_support:on_debugger_node(Config, fun() ->
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
                #{type => line, line => 4, module => test_reapply_module},
                #{type => line, line => 5, module => test_reapply_module}
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
                #{type => line, line => 4, module => test_reapply_module},
                #{type => line, line => 5, module => test_reapply_module}
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
                #{type => line, line => 4, module => test_reapply_module},
                #{type => line, line => 5, module => test_reapply_module}
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

% ------------------------------------------------------------------
% Test cases for the substitute_line_breakpoints group
% ------------------------------------------------------------------

test_add_module_substitute_transfers_existing_breakpoints_to_substitute_module(Config) ->
    % Create original and substitute versions of test module
    OriginalSource = create_test_source(test_module),
    SubstituteModuleSource = create_test_source(test_module_substitute),

    edb_test_support:on_debugger_node(Config, fun() ->
        % Start peer node with the test module
        {ok, #{node := Node, modules := #{test_module := _}, peer := Peer, cookie := Cookie}} = edb_test_support:start_peer_node(
            Config, #{
                enable_debugging_mode => true,
                modules => [{source, OriginalSource}]
            }
        ),

        ok = edb:attach(#{node => Node, cookie => Cookie}),

        % Set breakpoints on lines 4 and 5
        ok = edb:add_breakpoint(test_module, 4),
        ok = edb:add_breakpoint(test_module, 5),

        % Compile and add the substitute module
        {ok, test_module_substitute, _SourceFilePath} = peer:call(Peer, edb_test_support, compile_module, [
            Config, {source, SubstituteModuleSource}, #{load_it => true}
        ]),
        ok = peer:call(Peer, edb_server, add_module_substitute, [test_module, test_module_substitute, []]),

        % Verify breakpoints are copied to the substitute module
        Breakpoints1 = edb:get_breakpoints(test_module),
        ?assertEqual(
            [
                #{type => line, line => 4, module => test_module},
                #{type => line, line => 5, module => test_module}
            ],
            Breakpoints1
        ),

        % Call the substitute module's test_function to verify that both breakpoints get hit
        _TestPid = erlang:spawn(fun() ->
            peer:call(Peer, test_module_substitute, test_function, [])
        end),

        % Wait for the test process to hit the breakpoint
        {ok, paused} = edb:wait(),

        % Breakpoint on line 4 is hit and reported as belonging to the original module
        Breakpoints2Map = edb:get_breakpoints_hit(),
        Breakpoints2 = maps:values(Breakpoints2Map),
        ?assertEqual(
            [#{type => line, line => 4, module => test_module}], Breakpoints2
        ),

        % Resume the test process and wait to hit the next breakpoint
        {ok, resumed} = edb:continue(),
        {ok, paused} = edb:wait(),

        % Breakpoint on line 5 is hit and reported as belonging to the original module
        Breakpoints3Map = edb:get_breakpoints_hit(),
        Breakpoints3 = maps:values(Breakpoints3Map),
        ?assertEqual(
            [#{type => line, line => 5, module => test_module}], Breakpoints3
        ),
        ok
    end),
    ok.

test_add_module_substitute_adds_new_breakpoints_to_substitute_module(Config) ->
    % Create original and substitute versions of test module
    OriginalSource = create_test_source(test_module),
    SubstituteModuleSource = create_test_source(test_module_substitute),

    edb_test_support:on_debugger_node(Config, fun() ->
        % Start peer node with the test module
        {ok, #{node := Node, modules := #{test_module := _}, peer := Peer, cookie := Cookie}} = edb_test_support:start_peer_node(
            Config, #{
                enable_debugging_mode => true,
                modules => [{source, OriginalSource}]
            }
        ),

        ok = edb:attach(#{node => Node, cookie => Cookie}),

        % Compile and add the substitute module
        {ok, test_module_substitute, _SourceFilePath} = peer:call(Peer, edb_test_support, compile_module, [
            Config, {source, SubstituteModuleSource}, #{load_it => true}
        ]),
        ok = peer:call(Peer, edb_server, add_module_substitute, [test_module, test_module_substitute, []]),

        % Set breakpoints on lines 4 and 5
        ok = edb:add_breakpoint(test_module, 4),
        ok = edb:add_breakpoint(test_module, 5),

        % Verify breakpoints are copied to the substitute module
        Breakpoints1 = edb:get_breakpoints(test_module),
        ?assertEqual(
            [
                #{type => line, line => 4, module => test_module},
                #{type => line, line => 5, module => test_module}
            ],
            Breakpoints1
        ),

        % Call the substitute module's test_function to verify that both breakpoints get hit
        _TestPid = erlang:spawn(fun() ->
            peer:call(Peer, test_module_substitute, test_function, [])
        end),

        % Wait for the test process to hit the breakpoint
        {ok, paused} = edb:wait(),

        % Breakpoint on line 4 is hit and reported as belonging to the original module
        Breakpoints2Map = edb:get_breakpoints_hit(),
        Breakpoints2 = maps:values(Breakpoints2Map),
        ?assertEqual(
            [#{type => line, line => 4, module => test_module}], Breakpoints2
        ),

        % Resume the test process and wait to hit the next breakpoint
        {ok, resumed} = edb:continue(),
        {ok, paused} = edb:wait(),

        % Breakpoint on line 5 is hit and reported as belonging to the original module
        Breakpoints3Map = edb:get_breakpoints_hit(),
        Breakpoints3 = maps:values(Breakpoints3Map),
        ?assertEqual(
            [#{type => line, line => 5, module => test_module}], Breakpoints3
        ),
        ok
    end),
    ok.

test_remove_module_substitute_transfers_breakpoints_back_to_original_module(Config) ->
    % Create original and substitute versions of test module
    OriginalSource = create_test_source(test_module),
    SubstituteModuleSource = create_test_source(test_module_substitute),

    edb_test_support:on_debugger_node(Config, fun() ->
        % Start peer node with the test modules
        {ok, #{
            node := Node, modules := #{test_module := _, test_module_substitute := _}, peer := Peer, cookie := Cookie
        }} = edb_test_support:start_peer_node(
            Config, #{
                enable_debugging_mode => true,
                modules => [{source, OriginalSource}, {source, SubstituteModuleSource}]
            }
        ),

        ok = edb:attach(#{node => Node, cookie => Cookie}),

        % Set up module substitute
        ok = peer:call(Peer, edb_server, add_module_substitute, [test_module, test_module_substitute, []]),

        % Set breakpoints on line 4 (which will be set on the substitute module)
        ok = edb:add_breakpoint(test_module, 4),

        % Sanity-check: Verify breakpoint is set on the substitute module
        Breakpoints1 = edb:get_breakpoints(test_module),
        ?assertEqual(
            [
                #{type => line, line => 4, module => test_module}
            ],
            Breakpoints1
        ),

        % Remove the module substitute
        ok = peer:call(Peer, edb_server, remove_module_substitute, [test_module_substitute]),

        % Verify breakpoint is transferred back to the original module
        Breakpoints2 = edb:get_breakpoints(test_module),
        ?assertEqual(
            [
                #{type => line, line => 4, module => test_module}
            ],
            Breakpoints2
        ),

        % Call the original module's test_function to verify that breakpoints get hit
        _TestPid = erlang:spawn(fun() ->
            peer:call(Peer, test_module, test_function, [])
        end),

        % Wait for the test process to hit the breakpoint
        {ok, paused} = edb:wait(),

        % Breakpoint on line 4 is hit
        Breakpoints3Map = edb:get_breakpoints_hit(),
        Breakpoints3 = maps:values(Breakpoints3Map),
        ?assertEqual(
            [#{type => line, line => 4, module => test_module}], Breakpoints3
        ),

        ok
    end),
    ok.

test_error_if_substitute_already_has_breakpoints_set(Config) ->
    % Create original and substitute versions of test module
    OriginalSource = create_test_source(test_module),
    SubstituteModuleSource = create_test_source(test_module_substitute),

    edb_test_support:on_debugger_node(Config, fun() ->
        % Start peer node with the test module
        {ok, #{node := Node, modules := #{test_module := _}, peer := Peer, cookie := Cookie}} = edb_test_support:start_peer_node(
            Config, #{
                enable_debugging_mode => true,
                modules => [{source, OriginalSource}]
            }
        ),

        ok = edb:attach(#{node => Node, cookie => Cookie}),

        % Compile and add the substitute module
        {ok, test_module_substitute, _SourceFilePath} = peer:call(Peer, edb_test_support, compile_module, [
            Config, {source, SubstituteModuleSource}, #{load_it => true}
        ]),

        % Substitute "already" has breakpoints set
        ok = edb:add_breakpoint(test_module_substitute, 4),

        Error = peer:call(Peer, edb_server, add_module_substitute, [test_module, test_module_substitute, []]),
        ?assertMatch({error, already_has_breakpoints}, Error),
        ok
    end),
    ok.

% ------------------------------------------------------------------
% Test cases for the substitute_function_breakpoints group
% ------------------------------------------------------------------

test_add_module_substitute_transfers_existing_function_breakpoints_to_substitute_module(Config) ->
    % Create original and substitute versions of test module
    OriginalSource = create_test_source(test_module),
    SubstituteModuleSource = create_test_source(test_module_substitute),

    edb_test_support:on_debugger_node(Config, fun() ->
        % Start peer node with the test module
        {ok, #{node := Node, modules := #{test_module := _}, peer := Peer, cookie := Cookie}} = edb_test_support:start_peer_node(
            Config, #{
                enable_debugging_mode => true,
                modules => [{source, OriginalSource}],
                compile_flags => [debug_info, beam_debug_info]
            }
        ),

        ok = edb:attach(#{node => Node, cookie => Cookie}),

        % Set function breakpoint on test_function/0
        ok = edb:add_function_breakpoint(test_module, test_function, 0),

        % Verify function breakpoint is set
        Breakpoints1 = edb:get_breakpoints(test_module),
        ?assertEqual(
            [
                #{type => function, module => test_module, function => {test_module, test_function, 0}}
            ],
            Breakpoints1
        ),

        % Compile and add the substitute module
        {ok, test_module_substitute, _SourceFilePath} = peer:call(Peer, edb_test_support, compile_module, [
            Config, {source, SubstituteModuleSource}, #{load_it => true, flags => [debug_info, beam_debug_info]}
        ]),
        ok = peer:call(Peer, edb_server, add_module_substitute, [test_module, test_module_substitute, []]),

        % Verify function breakpoint is still reported for original module
        Breakpoints2 = edb:get_breakpoints(test_module),
        ?assertEqual(
            [
                #{type => function, module => test_module, function => {test_module, test_function, 0}}
            ],
            Breakpoints2
        ),

        % Call the substitute module's test_function to verify that the function breakpoint gets hit
        _TestPid = erlang:spawn(fun() ->
            peer:call(Peer, test_module_substitute, test_function, [])
        end),

        % Wait for the test process to hit the breakpoint
        {ok, paused} = edb:wait(),

        % Function breakpoint is hit and reported as belonging to the original module
        Breakpoints3Map = edb:get_breakpoints_hit(),
        Breakpoints3 = maps:values(Breakpoints3Map),
        ?assertEqual(
            [#{type => function, module => test_module, function => {test_module, test_function, 0}}],
            Breakpoints3
        ),
        ok
    end),
    ok.

test_add_module_substitute_adds_new_function_breakpoints_to_substitute_module(Config) ->
    % Create original and substitute versions of test module
    OriginalSource = create_test_source(test_module),
    SubstituteModuleSource = create_test_source(test_module_substitute),

    edb_test_support:on_debugger_node(Config, fun() ->
        % Start peer node with the test module
        {ok, #{node := Node, modules := #{test_module := _}, peer := Peer, cookie := Cookie}} = edb_test_support:start_peer_node(
            Config, #{
                enable_debugging_mode => true,
                modules => [{source, OriginalSource}],
                compile_flags => [debug_info, beam_debug_info]
            }
        ),

        ok = edb:attach(#{node => Node, cookie => Cookie}),

        % Compile and add the substitute module
        {ok, test_module_substitute, _SourceFilePath} = peer:call(Peer, edb_test_support, compile_module, [
            Config, {source, SubstituteModuleSource}, #{load_it => true, flags => [debug_info, beam_debug_info]}
        ]),
        ok = peer:call(Peer, edb_server, add_module_substitute, [test_module, test_module_substitute, []]),

        % Set function breakpoint on test_function/0 after substitute is added
        ok = edb:add_function_breakpoint(test_module, test_function, 0),

        % Verify function breakpoint is set
        Breakpoints1 = edb:get_breakpoints(test_module),
        ?assertEqual(
            [
                #{type => function, module => test_module, function => {test_module, test_function, 0}}
            ],
            Breakpoints1
        ),

        % Call the substitute module's test_function to verify that the function breakpoint gets hit
        _TestPid = erlang:spawn(fun() ->
            peer:call(Peer, test_module_substitute, test_function, [])
        end),

        % Wait for the test process to hit the breakpoint
        {ok, paused} = edb:wait(),

        % Function breakpoint is hit and reported as belonging to the original module
        Breakpoints2Map = edb:get_breakpoints_hit(),
        Breakpoints2 = maps:values(Breakpoints2Map),
        ?assertEqual(
            [#{type => function, module => test_module, function => {test_module, test_function, 0}}],
            Breakpoints2
        ),
        ok
    end),
    ok.

test_remove_module_substitute_transfers_function_breakpoints_back_to_original_module(Config) ->
    % Create original and substitute versions of test module
    OriginalSource = create_test_source(test_module),
    SubstituteModuleSource = create_test_source(test_module_substitute),

    edb_test_support:on_debugger_node(Config, fun() ->
        % Start peer node with the test modules
        {ok, #{
            node := Node, modules := #{test_module := _, test_module_substitute := _}, peer := Peer, cookie := Cookie
        }} = edb_test_support:start_peer_node(
            Config, #{
                enable_debugging_mode => true,
                modules => [{source, OriginalSource}, {source, SubstituteModuleSource}],
                compile_flags => [debug_info, beam_debug_info]
            }
        ),

        ok = edb:attach(#{node => Node, cookie => Cookie}),

        % Set up module substitute
        ok = peer:call(Peer, edb_server, add_module_substitute, [test_module, test_module_substitute, []]),

        % Set function breakpoint on test_function/0 (which will be set on the substitute module)
        ok = edb:add_function_breakpoint(test_module, test_function, 0),

        % Sanity-check: Verify function breakpoint is set on the substitute module
        Breakpoints1 = edb:get_breakpoints(test_module),
        ?assertEqual(
            [
                #{type => function, module => test_module, function => {test_module, test_function, 0}}
            ],
            Breakpoints1
        ),

        % Remove the module substitute
        ok = peer:call(Peer, edb_server, remove_module_substitute, [test_module_substitute]),

        % Verify function breakpoint is transferred back to the original module
        Breakpoints2 = edb:get_breakpoints(test_module),
        ?assertEqual(
            [
                #{type => function, module => test_module, function => {test_module, test_function, 0}}
            ],
            Breakpoints2
        ),

        % Call the original module's test_function to verify that function breakpoint gets hit
        _TestPid = erlang:spawn(fun() ->
            peer:call(Peer, test_module, test_function, [])
        end),

        % Wait for the test process to hit the breakpoint
        {ok, paused} = edb:wait(),

        % Function breakpoint is hit
        Breakpoints3Map = edb:get_breakpoints_hit(),
        Breakpoints3 = maps:values(Breakpoints3Map),
        ?assertEqual(
            [#{type => function, module => test_module, function => {test_module, test_function, 0}}],
            Breakpoints3
        ),

        ok
    end),
    ok.

% ------------------------------------------------------------------
% Test cases for the substitute_stepping group
% ------------------------------------------------------------------
test_add_module_substitute_transfers_stepping_breakpoints(Config) ->
    ModuleSource1 =
        "-module(test_module).                  %L01\n"
        "-export([test_function/0]).            %L02\n"
        "test_function() ->                     %L03\n"
        "    A = other_module:test_function(),  %L04\n"
        "    B = A,                             %L05\n"
        "    B.                                 %L06\n",

    ModuleSource2 =
        "-module(other_module).                 %L01\n"
        "-export([test_function/0]).            %L02\n"
        "test_function() ->                     %L03\n"
        "    A = ok,                            %L04\n"
        "    C = A,                             %L05\n"
        "    C.                                 %L06\n",

    ModuleSource3 =
        "-module(other_module_sub).             %L01\n"
        "-export([test_function/0]).            %L02\n"
        "test_function() ->                     %L03\n"
        "    A = ok,                            %L04\n"
        "    C = A,                             %L05\n"
        "    C.                                 %L06\n",

    edb_test_support:on_debugger_node(Config, fun() ->
        % Start peer node with the test module
        {ok, #{
            node := Node,
            modules := #{test_module := _, other_module := _, other_module_sub := _},
            peer := Peer,
            cookie := Cookie
        }} = edb_test_support:start_peer_node(
            Config, #{
                enable_debugging_mode => true,
                modules => [{source, ModuleSource1}, {source, ModuleSource2}, {source, ModuleSource3}]
            }
        ),

        ok = edb:attach(#{node => Node, cookie => Cookie}),

        % Set breakpoint at test_module:4 and other_module:5
        ok = edb:add_breakpoint(test_module, 4),
        ok = edb:add_breakpoint(other_module, 5),

        % Compile the substitute module
        {ok, other_module_sub, _SourceFilePath} = peer:call(Peer, edb_test_support, compile_module, [
            Config, {source, ModuleSource3}, #{load_it => true, flags => [beam_debug_info]}
        ]),

        % Call the substitute module's test_function to verify that the breakpoint gets hit
        _TestPid = erlang:spawn(fun() ->
            peer:call(Peer, test_module, test_function, [])
        end),

        {ok, paused} = edb:wait(),

        ProcessMap = edb:processes([current_bp]),
        [PausedPid | []] = [
            Pid
         || Pid := #{current_bp := {line, 4}} <- ProcessMap
        ],

        % Step into other_module:test_function()
        ok = edb:step_in(PausedPid),

        % Add substitute for other_module
        ok = erpc:call(Node, edb_server, add_module_substitute, [other_module, other_module_sub, []]),

        {ok, paused} = edb:wait(),

        {ok, [#{line := Line, mfa := MFA} | _]} = edb:stack_frames(PausedPid),
        ?assertEqual({4, {other_module, test_function, 0}}, {Line, MFA}),

        % Step over to other_module:5
        ok = edb:step_over(PausedPid),
        {ok, paused} = edb:wait(),

        {ok, [#{line := Line2, mfa := MFA2} | _]} = edb:stack_frames(PausedPid),
        ?assertEqual({5, {other_module, test_function, 0}}, {Line2, MFA2}),

        % Step out of other_module:test_function()
        ok = edb:step_out(PausedPid),
        {ok, paused} = edb:wait(),

        {ok, [#{line := Line3, mfa := MFA3} | _]} = edb:stack_frames(PausedPid),
        ?assertEqual({5, {test_module, test_function, 0}}, {Line3, MFA3}),
        ok
    end),

    ok.

test_additional_frames_are_added_in_step_patterns(Config) ->
    ModuleSource1 =
        "-module(foo).                 %L01\n"
        "-export([test_function/0]).            %L02\n"
        "test_function() ->                     %L03\n"
        "    A = foo_sub:test_function() + 1,                            %L04\n"
        "    C = A,                             %L05\n"
        "    C.                                 %L06\n",

    ModuleSource2 =
        "-module(foo_sub).             %L01\n"
        "-export([test_function/0]).            %L02\n"
        "test_function() ->                     %L03\n"
        "    A = 1,                            %L04\n"
        "    C = A,                             %L05\n"
        "    C.                                 %L06\n",

    edb_test_support:on_debugger_node(Config, fun() ->
        % Start peer node with the test module
        {ok, #{
            node := Node,
            modules := #{foo := _, foo_sub := _},
            peer := Peer,
            cookie := Cookie
        }} = edb_test_support:start_peer_node(
            Config, #{
                enable_debugging_mode => true,
                modules => [
                    {source, ModuleSource1}, {source, ModuleSource2}
                ]
            }
        ),

        ok = edb:attach(#{node => Node, cookie => Cookie}),

        % Set breakpoint at test_module:4 and foo:5
        ok = edb:add_breakpoint(foo, 4),
        % ok = edb:add_breakpoint(foo, 5),

        % Compile the substitute module
        {ok, foo_sub, _SourceFilePath} = peer:call(Peer, edb_test_support, compile_module, [
            Config, {source, ModuleSource2}, #{load_it => true, flags => [debug_info, beam_debug_info]}
        ]),
        % Add substitute for foo with added frames
        ok = erpc:call(Node, edb_server, add_module_substitute, [
            foo, foo_sub, [{foo, test_function, 0}]
        ]),

        % Call the module's test_function to verify that the breakpoint gets hit
        _TestPid = erlang:spawn(fun() ->
            peer:call(Peer, foo, test_function, [])
        end),

        {ok, paused} = edb:wait(),

        ProcessMap = edb:processes([current_bp]),
        [PausedPid | []] = [
            Pid
         || Pid := #{current_bp := {line, 4}} <- ProcessMap
        ],

        edb:clear_breakpoint(foo, 4),

        % Step into foo_sub:test_function()
        ok = edb:step_in(PausedPid),
        {ok, paused} = edb:wait(),

        {ok, [#{line := Line, mfa := MFA} | _]} = edb:stack_frames(PausedPid),
        ?assertEqual({4, {foo, test_function, 0}}, {Line, MFA}),

        % Step over to foo_sub:5
        ok = edb:step_over(PausedPid),
        {ok, paused} = edb:wait(),

        {ok, [#{line := Line2, mfa := MFA2} | _]} = edb:stack_frames(PausedPid),
        ?assertEqual({5, {foo, test_function, 0}}, {Line2, MFA2}),

        ok
    end),
    ok.

test_stepping_breakpoints_work_after_removing_substitute(Config) ->
    ModuleSource1 =
        "-module(test_module).                                                                  %L01\n"
        "-export([test_function/0]).                                                            %L02\n"
        "test_function() ->                                                                     %L03\n"
        "    ok = edb_server:add_module_substitute(other_module, other_module_sub, []),         %L04\n"
        "    A = other_module_sub:test_function(),                                              %L05\n"
        "    ok = edb_server:remove_module_substitute(other_module_sub),                        %L06\n"
        "    B = other_module:test_function(),                                                  %L07\n"
        "    B.                                                                                 %L08\n",

    ModuleSource2 =
        "-module(other_module).                 %L01\n"
        "-export([test_function/0]).            %L02\n"
        "test_function() ->                     %L03\n"
        "    A = ok,                            %L04\n"
        "    C = A,                             %L05\n"
        "    C.                                 %L06\n",

    ModuleSource3 =
        "-module(other_module_sub).             %L01\n"
        "-export([test_function/0]).            %L02\n"
        "test_function() ->                     %L03\n"
        "    A = ok,                            %L04\n"
        "    C = A,                             %L05\n"
        "    C.                                 %L06\n",

    edb_test_support:on_debugger_node(Config, fun() ->
        % Start peer node with the test module
        {ok, #{
            node := Node,
            modules := #{test_module := _, other_module := _, other_module_sub := _},
            peer := Peer,
            cookie := Cookie
        }} = edb_test_support:start_peer_node(
            Config, #{
                enable_debugging_mode => true,
                modules => [{source, ModuleSource1}, {source, ModuleSource2}, {source, ModuleSource3}]
            }
        ),

        ok = edb:attach(#{node => Node, cookie => Cookie}),

        % Set breakpoint at test_module:4 and other_module:5
        ok = edb:add_breakpoint(test_module, 5),

        % Compile the substitute module
        {ok, other_module_sub, _SourceFilePath} = peer:call(Peer, edb_test_support, compile_module, [
            Config, {source, ModuleSource3}, #{load_it => true, flags => [beam_debug_info]}
        ]),

        % Call the test_function to verify that the breakpoint gets hit with substitute
        _TestPid1 = erlang:spawn(fun() ->
            peer:call(Peer, test_module, test_function, [])
        end),

        {ok, paused} = edb:wait(),

        ProcessMap = edb:processes([current_bp]),
        [PausedPid | []] = [
            Pid
         || Pid := #{current_bp := {line, 5}} <- ProcessMap
        ],

        % Step into other_module:test_function() (which should use substitute)
        ok = edb:step_in(PausedPid),
        {ok, paused} = edb:wait(),

        {ok, [#{line := Line, mfa := MFA} | _]} = edb:stack_frames(PausedPid),
        ?assertEqual({4, {other_module, test_function, 0}}, {Line, MFA}),

        % Step over to other_module:5
        ok = edb:step_over(PausedPid),
        {ok, paused} = edb:wait(),

        {ok, [#{line := Line2, mfa := MFA2} | _]} = edb:stack_frames(PausedPid),
        ?assertEqual({5, {other_module, test_function, 0}}, {Line2, MFA2}),

        % Step out and continue to finish this test process
        ok = edb:step_out(PausedPid),
        {ok, paused} = edb:wait(),

        ok = edb:step_over(PausedPid),
        {ok, paused} = edb:wait(),

        {ok, [#{line := Line8, mfa := MFA8} | _]} = edb:stack_frames(PausedPid),
        ?assertEqual({7, {test_module, test_function, 0}}, {Line8, MFA8}),

        % Step into other_module:test_function() (should now use original module)
        ok = edb:step_in(PausedPid),
        {ok, paused} = edb:wait(),

        {ok, [#{line := Line3, mfa := MFA3} | _]} = edb:stack_frames(PausedPid),
        ?assertEqual({4, {other_module, test_function, 0}}, {Line3, MFA3}),

        % Step over to other_module:5
        ok = edb:step_over(PausedPid),
        {ok, paused} = edb:wait(),

        {ok, [#{line := Line4, mfa := MFA4} | _]} = edb:stack_frames(PausedPid),
        ?assertEqual({5, {other_module, test_function, 0}}, {Line4, MFA4}),

        % Step out to verify we return to test_module correctly
        ok = edb:step_out(PausedPid),
        {ok, paused} = edb:wait(),

        {ok, [#{line := Line5, mfa := MFA5} | _]} = edb:stack_frames(PausedPid),
        ?assertEqual({8, {test_module, test_function, 0}}, {Line5, MFA5}),
        ok
    end),
    ok.

% ------------------------------------------------------------------
% Test cases for the substitute_reporting group
% ------------------------------------------------------------------

test_original_module_is_reported_in_stack_frames(Config) ->
    % Create original and substitute versions of test module
    OriginalSource = create_test_source(test_module),
    SubstituteModuleSource = create_test_source(test_module_substitute),

    edb_test_support:on_debugger_node(Config, fun() ->
        % Start peer node with the test module
        {ok, #{node := Node, modules := #{test_module := _}, peer := Peer, cookie := Cookie}} = edb_test_support:start_peer_node(
            Config, #{
                enable_debugging_mode => true,
                modules => [{source, OriginalSource}]
            }
        ),

        ok = edb:attach(#{node => Node, cookie => Cookie}),

        % Compile and add the substitute module
        {ok, test_module_substitute, _SourceFilePath} = peer:call(Peer, edb_test_support, compile_module, [
            Config, {source, SubstituteModuleSource}, #{load_it => true}
        ]),
        ok = peer:call(Peer, edb_server, add_module_substitute, [test_module, test_module_substitute, []]),

        % Set breakpoint on line 4
        ok = edb:add_breakpoint(test_module, 4),

        % Call the substitute module's test_function to verify that the breakpoint gets hit
        _TestPid = erlang:spawn(fun() ->
            peer:call(Peer, test_module_substitute, test_function, [])
        end),

        % Wait for the test process to hit the breakpoint
        {ok, paused} = edb:wait(),

        % Verify that the stack frames report the original module
        ProcessMap = edb:processes([current_bp]),
        [PausedPid | []] = [
            Pid
         || Pid := #{current_bp := {line, 4}} <- ProcessMap
        ],
        {ok, [#{mfa := MFA, line := Line, source := Source} | _OtherFrames]} = edb:stack_frames(PausedPid),
        AccSource =
            case Source of
                undefined -> [];
                _ -> Source
            end,
        ?assertEqual({test_module, test_function, 0}, MFA),
        ?assertEqual(4, Line),
        ?assert(lists:suffix("test_module.erl", AccSource)),
        ok
    end),
    ok.

test_original_module_is_reported_in_paused_event_for_line_breakpoint(Config) ->
    % Create original and substitute versions of test module
    OriginalSource = create_test_source(test_module),
    SubstituteModuleSource = create_test_source(test_module_substitute),

    edb_test_support:on_debugger_node(Config, fun() ->
        % Start peer node with the test module
        {ok, #{node := Node, modules := #{test_module := _}, peer := Peer, cookie := Cookie}} = edb_test_support:start_peer_node(
            Config, #{
                enable_debugging_mode => true,
                modules => [{source, OriginalSource}]
            }
        ),

        ok = edb:attach(#{node => Node, cookie => Cookie}),

        % Subscribe to events
        {ok, Subscription} = edb:subscribe(),

        % Compile and add the substitute module
        {ok, test_module_substitute, _SourceFilePath} = peer:call(Peer, edb_test_support, compile_module, [
            Config, {source, SubstituteModuleSource}, #{load_it => true}
        ]),
        ok = peer:call(Peer, edb_server, add_module_substitute, [test_module, test_module_substitute, []]),

        % Set breakpoint on line 4
        ok = edb:add_breakpoint(test_module, 4),

        % Call the substitute module's test_function to verify that the breakpoint gets hit
        erlang:spawn(fun() ->
            peer:call(Peer, test_module_substitute, test_function, [])
        end),

        % Wait for the test process to hit the breakpoint
        {ok, paused} = edb:wait(),

        % Check the paused event - MFA should report the original module
        receive
            {edb_event, Subscription, {paused, {breakpoint, _SomePid, {test_module, test_function, 0}, {line, 4}}}} ->
                ok;
            {edb_event, Subscription, Other} ->
                error({unexpected_event, Other})
        after 2000 ->
            error(~"Timeout waiting for paused event")
        end,

        edb:unsubscribe(Subscription),
        ok
    end),
    ok.

test_original_module_is_reported_in_paused_event_for_function_breakpoint(Config) ->
    % Create original and substitute versions of test module
    OriginalSource = create_test_source(test_module),
    SubstituteModuleSource = create_test_source(test_module_substitute),

    edb_test_support:on_debugger_node(Config, fun() ->
        % Start peer node with the test module
        {ok, #{node := Node, modules := #{test_module := _}, peer := Peer, cookie := Cookie}} = edb_test_support:start_peer_node(
            Config, #{
                enable_debugging_mode => true,
                modules => [{source, OriginalSource}],
                compile_flags => [debug_info, beam_debug_info]
            }
        ),

        ok = edb:attach(#{node => Node, cookie => Cookie}),

        % Subscribe to events
        {ok, Subscription} = edb:subscribe(),

        % Compile and add the substitute module
        {ok, test_module_substitute, _SourceFilePath} = peer:call(Peer, edb_test_support, compile_module, [
            Config, {source, SubstituteModuleSource}, #{load_it => true, flags => [debug_info, beam_debug_info]}
        ]),
        ok = peer:call(Peer, edb_server, add_module_substitute, [test_module, test_module_substitute, []]),

        % Set function breakpoint on test_function/0
        ok = edb:add_function_breakpoint(test_module, test_function, 0),

        % Call the substitute module's test_function to verify that the function breakpoint gets hit
        erlang:spawn(fun() ->
            peer:call(Peer, test_module_substitute, test_function, [])
        end),

        % Wait for the test process to hit the breakpoint
        {ok, paused} = edb:wait(),

        % Check the paused event - MFA should report the original module
        receive
            {edb_event, Subscription,
                {paused, {function_breakpoint, _SomePid, {test_module, test_function, 0}, {line, 4}}}} ->
                ok;
            {edb_event, Subscription, Other} ->
                error({unexpected_event, Other})
        after 2000 ->
            error(~"Timeout waiting for paused event")
        end,

        edb:unsubscribe(Subscription),
        ok
    end),
    ok.

% ------------------------------------------------------------------
% Test cases for the substitute_multiplicity group
% ------------------------------------------------------------------

test_add_module_substitute_handles_transitive_substitutes(Config) ->
    % Create three modules: original, intermediate, and final
    OriginalSource = create_test_source(test_module_original),
    IntermediateSource = create_test_source(test_module_intermediate),
    FinalSource = create_test_source(test_module_final),

    edb_test_support:on_debugger_node(Config, fun() ->
        % Start peer node with all three modules
        {ok, #{
            node := Node,
            modules := #{
                test_module_original := _,
                test_module_intermediate := _,
                test_module_final := _
            },
            peer := Peer,
            cookie := Cookie
        }} = edb_test_support:start_peer_node(
            Config, #{
                enable_debugging_mode => true,
                modules => [
                    {source, OriginalSource},
                    {source, IntermediateSource},
                    {source, FinalSource}
                ]
            }
        ),

        ok = edb:attach(#{node => Node, cookie => Cookie}),

        ok = edb:add_breakpoint(test_module_original, 4),

        % Compile and set up transitive substitutes
        {ok, test_module_intermediate, _} = peer:call(Peer, edb_test_support, compile_module, [
            Config, {source, IntermediateSource}, #{load_it => true}
        ]),
        {ok, test_module_final, _} = peer:call(Peer, edb_test_support, compile_module, [
            Config, {source, FinalSource}, #{load_it => true}
        ]),
        ok = peer:call(Peer, edb_server, add_module_substitute, [test_module_original, test_module_intermediate, []]),
        ok = peer:call(Peer, edb_server, add_module_substitute, [test_module_intermediate, test_module_final, []]),

        % Verify breakpoint is transferred to final module
        Breakpoints1 = edb:get_breakpoints(test_module_original),
        ?assertEqual(
            [#{type => line, line => 4, module => test_module_original}],
            Breakpoints1
        ),

        % Clear the breakpoint on the original module
        ok = edb:clear_breakpoint(test_module_original, 4),

        % Verify breakpoint is cleared from the final module
        Breakpoints2 = edb:get_breakpoints(test_module_original),
        ?assertEqual([], Breakpoints2),

        % Set breakpoint on original module
        ok = edb:add_breakpoint(test_module_original, 4),

        % Verify breakpoint is set on final module
        Breakpoints3 = edb:get_breakpoints(test_module_original),
        ?assertEqual(
            [#{type => line, line => 4, module => test_module_original}],
            Breakpoints3
        ),

        % Call the final module's test_function to verify the breakpoint gets hit
        _TestPid = erlang:spawn(fun() ->
            peer:call(Peer, test_module_final, test_function, [])
        end),

        % Wait for the test process to hit the breakpoint
        {ok, paused} = edb:wait(),

        % Breakpoint is hit and reported as belonging to the original module
        BreakpointsHitMap = edb:get_breakpoints_hit(),
        BreakpointsHit = maps:values(BreakpointsHitMap),
        ?assertEqual(
            [#{type => line, line => 4, module => test_module_original}],
            BreakpointsHit
        ),

        ok
    end),
    ok.

test_remove_module_substitute_handles_transitive_substitutes(Config) ->
    % Create three modules: original, intermediate, and final
    OriginalSource = create_test_source(test_module_original),
    IntermediateSource = create_test_source(test_module_intermediate),
    FinalSource = create_test_source(test_module_final),

    edb_test_support:on_debugger_node(Config, fun() ->
        % Start peer node with all three modules
        {ok, #{
            node := Node,
            modules := #{
                test_module_original := _,
                test_module_intermediate := _,
                test_module_final := _
            },
            peer := Peer,
            cookie := Cookie
        }} = edb_test_support:start_peer_node(
            Config, #{
                enable_debugging_mode => true,
                modules => [
                    {source, OriginalSource},
                    {source, IntermediateSource},
                    {source, FinalSource}
                ]
            }
        ),

        ok = edb:attach(#{node => Node, cookie => Cookie}),

        ok = peer:call(Peer, edb_server, add_module_substitute, [test_module_original, test_module_intermediate, []]),
        ok = peer:call(Peer, edb_server, add_module_substitute, [test_module_intermediate, test_module_final, []]),

        % Set breakpoint on original module (which will be set on the final module)
        ok = edb:add_breakpoint(test_module_original, 4),

        % Sanity-check: Verify breakpoint is set on the final module
        Breakpoints1 = edb:get_breakpoints(test_module_original),
        ?assertEqual(
            [
                #{type => line, line => 4, module => test_module_original}
            ],
            Breakpoints1
        ),

        % Remove the final module substitute
        ok = peer:call(Peer, edb_server, remove_module_substitute, [test_module_final]),

        % Verify breakpoint is still in the intermediate module
        Breakpoints2 = edb:get_breakpoints(test_module_original),
        ?assertEqual(
            [
                #{type => line, line => 4, module => test_module_original}
            ],
            Breakpoints2
        ),

        % Call the intermediate module's test_function to verify that breakpoint gets hit
        _TestPid = erlang:spawn(fun() ->
            peer:call(Peer, test_module_intermediate, test_function, [])
        end),

        % Wait for the test process to hit the breakpoint
        {ok, paused} = edb:wait(),

        % Breakpoint on line 4 is hit
        BreakpointsHitMap = edb:get_breakpoints_hit(),
        BreakpointsHit = maps:values(BreakpointsHitMap),
        ?assertEqual(
            [#{type => line, line => 4, module => test_module_original}], BreakpointsHit
        ),

        edb:continue(),

        % Remove the intermediate module substitute
        ok = peer:call(Peer, edb_server, remove_module_substitute, [test_module_intermediate]),

        % Verify breakpoint is transferred back to the original module
        % and the chain of substitutes is broken
        Breakpoints3 = edb:get_breakpoints(test_module_original),
        ?assertEqual(
            [
                #{type => line, line => 4, module => test_module_original}
            ],
            Breakpoints3
        ),

        % Call the original module's test_function to verify that breakpoint gets hit
        _TestPid2 = erlang:spawn(fun() ->
            peer:call(Peer, test_module_original, test_function, [])
        end),

        % Wait for the test process to hit the breakpoint
        {ok, paused} = edb:wait(),

        % Breakpoint on line 4 is hit
        BreakpointsHitMap2 = edb:get_breakpoints_hit(),
        BreakpointsHit2 = maps:values(BreakpointsHitMap2),
        ?assertEqual(
            [#{type => line, line => 4, module => test_module_original}], BreakpointsHit2
        ),

        ok
    end),
    ok.

test_error_if_module_already_has_a_substitute(Config) ->
    % Create original and substitute versions of test module
    OriginalSource = create_test_source(test_module),
    SubstituteModuleSource = create_test_source(test_module_substitute),
    BadSubstituteModuleSource = create_test_source(bad_test_module_substitute),

    edb_test_support:on_debugger_node(Config, fun() ->
        % Start peer node with the test module
        {ok, #{
            node := Node, modules := #{test_module := _, test_module_substitute := _}, peer := Peer, cookie := Cookie
        }} = edb_test_support:start_peer_node(
            Config, #{
                enable_debugging_mode => true,
                modules => [{source, OriginalSource}, {source, SubstituteModuleSource}]
            }
        ),

        ok = edb:attach(#{node => Node, cookie => Cookie}),

        ok = peer:call(Peer, edb_server, add_module_substitute, [test_module, test_module_substitute, []]),

        % Compile and add the bad substitute module
        {ok, bad_test_module_substitute, _SourceFilePath} = peer:call(Peer, edb_test_support, compile_module, [
            Config, {source, BadSubstituteModuleSource}, #{load_it => true}
        ]),
        Error = peer:call(Peer, edb_server, add_module_substitute, [test_module, bad_test_module_substitute, []]),
        ?assertMatch({error, already_substituted}, Error),
        ok
    end),
    ok.

test_error_if_substitute_is_already_a_substitute(Config) ->
    % Create three modules: original1, original2, and substitute
    Original1Source = create_test_source(test_module_original1),
    Original2Source = create_test_source(test_module_original2),
    SubstituteModuleSource = create_test_source(test_module_substitute),

    edb_test_support:on_debugger_node(Config, fun() ->
        % Start peer node with all three modules
        {ok, #{
            node := Node,
            modules := #{
                test_module_original1 := _,
                test_module_original2 := _,
                test_module_substitute := _
            },
            peer := Peer,
            cookie := Cookie
        }} = edb_test_support:start_peer_node(
            Config, #{
                enable_debugging_mode => true,
                modules => [
                    {source, Original1Source},
                    {source, Original2Source},
                    {source, SubstituteModuleSource}
                ]
            }
        ),

        ok = edb:attach(#{node => Node, cookie => Cookie}),

        % Set up first substitution: original1 -> substitute
        ok = peer:call(Peer, edb_server, add_module_substitute, [test_module_original1, test_module_substitute, []]),

        % Try to set up second substitution: original2 -> substitute
        % This should fail because substitute is already a substitute for original1
        Error = peer:call(Peer, edb_server, add_module_substitute, [test_module_original2, test_module_substitute, []]),
        ?assertMatch({error, is_already_a_substitute}, Error),
        ok
    end),
    ok.

test_error_if_try_removing_intermediate_substitute(Config) ->
    % Create three modules: original, intermediate, and final
    OriginalSource = create_test_source(test_module_original),
    IntermediateSource = create_test_source(test_module_intermediate),
    FinalSource = create_test_source(test_module_final),

    edb_test_support:on_debugger_node(Config, fun() ->
        % Start peer node with all three modules
        {ok, #{
            node := Node,
            modules := #{
                test_module_original := _,
                test_module_intermediate := _,
                test_module_final := _
            },
            peer := Peer,
            cookie := Cookie
        }} = edb_test_support:start_peer_node(
            Config, #{
                enable_debugging_mode => true,
                modules => [
                    {source, OriginalSource},
                    {source, IntermediateSource},
                    {source, FinalSource}
                ]
            }
        ),

        ok = edb:attach(#{node => Node, cookie => Cookie}),

        ok = peer:call(Peer, edb_server, add_module_substitute, [test_module_original, test_module_intermediate, []]),
        ok = peer:call(Peer, edb_server, add_module_substitute, [test_module_intermediate, test_module_final, []]),

        % Remove the intermediate module substitute
        Error = peer:call(Peer, edb_server, remove_module_substitute, [test_module_intermediate]),
        ?assertMatch({error, has_dependent_substitute}, Error)
    end),
    ok.

test_error_if_try_removing_non_existent_substitute(Config) ->
    % Create original and substitute versions of test module
    OriginalSource = create_test_source(test_module),
    SubstituteModuleSource = create_test_source(test_module_substitute),

    edb_test_support:on_debugger_node(Config, fun() ->
        % Start peer node with the test module
        {ok, #{
            node := Node, modules := #{test_module := _, test_module_substitute := _}, peer := Peer, cookie := Cookie
        }} = edb_test_support:start_peer_node(
            Config, #{
                enable_debugging_mode => true,
                modules => [{source, OriginalSource}, {source, SubstituteModuleSource}]
            }
        ),

        ok = edb:attach(#{node => Node, cookie => Cookie}),

        ok = peer:call(Peer, edb_server, add_module_substitute, [test_module, test_module_substitute, []]),
        Error = peer:call(Peer, edb_server, remove_module_substitute, [test_module]),
        ?assertMatch({error, not_a_substitute}, Error),
        ok
    end),
    ok.

% -----------------------------------------------------------------------------
% Helpers
% -----------------------------------------------------------------------------
-spec create_test_source(module()) -> string().
create_test_source(Module) ->
    SourceChars =
        io_lib:format(
            "-module(~p).                       %L01\n"
            "-export([test_function/0]).        %L02\n"
            "test_function() ->                 %L03\n"
            "    A = ok,                        %L04\n"
            "    B = A,                         %L05\n"
            "    B.                             %L06\n",
            [Module]
        ),
    lists:flatten(SourceChars).
