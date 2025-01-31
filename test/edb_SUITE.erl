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
-module(edb_SUITE).

%% erlfmt:ignore
% @fb-only: 

% @fb-only: 
-include_lib("stdlib/include/assert.hrl").

%% Test server specific exports
-export([all/0, groups/0, suite/0]).
-export([init_per_suite/1, end_per_suite/1]).
-export([init_per_group/2, end_per_group/2]).
-export([init_per_testcase/2, end_per_testcase/2]).

%% Test cases for the test_subscriptions group
-export([test_can_subscribe_and_unsubscribe/1]).
-export([test_terminated_event_is_sent/1]).

%% Test cases for the test_pause group
-export([test_pause_pauses/1]).
-export([test_pause_is_idempotent/1]).

%% Test for the test_breakpoints group
-export([test_wait_waits_for_breakpoint_hit/1]).
-export([test_continue_continues/1]).
-export([test_hitting_a_breakpoint_suspends_other_processes/1]).
-export([test_processes_reports_running_and_paused_processes/1]).
-export([test_excluded_processes_reports_excluded_processes/1]).
-export([test_excluded_processes_dont_hit_breakpoints/1]).
-export([test_excluding_a_process_makes_it_resume/1]).
-export([test_can_override_excluded_processes_by_other_reasons/1]).
-export([test_can_reinclude_previously_excluded_processes/1]).
-export([test_including_a_process_can_suspend_it_immediately/1]).
-export([test_clear_breakpoint_clears_breakpoints/1]).
-export([test_clear_breakpoints_clears_all_breakpoints/1]).
-export([test_get_breakpoints_reports_current_set_breakpoints/1]).

%% Test cases for the test_step_over group
-export([test_step_over_goes_to_next_line/1]).
-export([test_step_over_skips_same_name_fun_call/1]).
-export([test_step_over_fails_on_running_process/1]).
-export([test_step_over_to_caller_on_return/1]).
-export([test_step_over_within_and_out_of_closure/1]).
-export([test_step_over_within_and_out_of_external_closure/1]).
-export([test_step_over_into_local_handler/1]).
-export([test_step_over_into_caller_handler/1]).
-export([test_step_over_progresses_from_breakpoint/1]).
-export([test_breakpoint_consumes_step/1]).
-export([test_multiprocess_parallel_steps/1]).

%% Test cases for the test_step_out group
-export([test_step_out_of_external_closure/1]).
-export([test_step_out_into_caller_handler/1]).

%% Test cases for the test_code_inspection group
-export([test_fetch_fun_block_surrounding/1]).

%% Test cases for the test_stackframes group
-export([test_shows_stackframes_of_process_in_breakpoint/1]).
-export([test_shows_stackframes_of_paused_processes_not_in_breakpoint/1]).
-export([test_shows_stackframes_of_stepping_process/1]).
-export([test_can_control_max_size_of_terms_in_vars_for_process_in_bp/1]).
-export([test_can_control_max_size_of_terms_in_vars_for_process_not_in_bp/1]).
-export([test_doesnt_show_stackframes_for_running_processes/1]).
-export([test_shows_a_path_that_exists_for_otp_sources/1]).

%% Test cases for the test_format group
-export([test_format_works/1]).

%% erlfmt:ignore
suite() ->
    [
        % @fb-only: 
        {timetrap, {minutes, 10}}
    ].

groups() ->
    [
        {test_subscriptions, [], [
            test_can_subscribe_and_unsubscribe,
            test_terminated_event_is_sent
        ]},
        {test_pause, [], [
            test_pause_pauses,
            test_pause_is_idempotent
        ]},
        {test_breakpoints, [], [
            test_wait_waits_for_breakpoint_hit,
            test_continue_continues,
            test_hitting_a_breakpoint_suspends_other_processes,
            test_processes_reports_running_and_paused_processes,
            test_excluded_processes_reports_excluded_processes,
            test_excluded_processes_dont_hit_breakpoints,
            test_excluding_a_process_makes_it_resume,
            test_can_override_excluded_processes_by_other_reasons,
            test_can_reinclude_previously_excluded_processes,
            test_including_a_process_can_suspend_it_immediately,
            test_clear_breakpoint_clears_breakpoints,
            test_clear_breakpoints_clears_all_breakpoints,
            test_get_breakpoints_reports_current_set_breakpoints
        ]},
        {test_step_over, [], [
            test_step_over_goes_to_next_line,
            test_step_over_skips_same_name_fun_call,
            test_step_over_fails_on_running_process,
            test_step_over_to_caller_on_return,
            test_step_over_within_and_out_of_closure,
            test_step_over_within_and_out_of_external_closure,
            test_step_over_into_local_handler,
            test_step_over_into_caller_handler,
            test_step_over_progresses_from_breakpoint,
            test_breakpoint_consumes_step,
            test_multiprocess_parallel_steps
        ]},
        {test_step_out, [], [
            test_step_out_of_external_closure,
            test_step_out_into_caller_handler
        ]},
        {test_code_inspection, [], [
            test_fetch_fun_block_surrounding
        ]},

        {test_stackframes, [], [
            test_shows_stackframes_of_process_in_breakpoint,
            test_shows_stackframes_of_paused_processes_not_in_breakpoint,
            test_shows_stackframes_of_stepping_process,
            test_can_control_max_size_of_terms_in_vars_for_process_in_bp,
            test_can_control_max_size_of_terms_in_vars_for_process_not_in_bp,
            test_doesnt_show_stackframes_for_running_processes,
            test_shows_a_path_that_exists_for_otp_sources
        ]},
        {test_format, [], [
            test_format_works
        ]}
    ].

all() ->
    [
        {group, test_subscriptions},
        {group, test_pause},
        {group, test_breakpoints},
        {group, test_step_over},
        {group, test_step_out},
        {group, test_code_inspection},
        {group, test_stackframes},
        {group, test_format}
    ].

init_per_suite(Config) ->
    erts_debug:set_internal_state(available_internal_state, true),
    erts_debug:set_internal_state(debugger_support, true),
    erts_debug:set_internal_state(available_internal_state, false),
    ok = edb:attach(#{node => node()}),
    compile_dummy_apps(Config),
    Config.

end_per_suite(_Config) ->
    ok.

init_per_group(Group, Config0) ->
    DataDir = proplists:get_value(data_dir, Config0),
    PrivDir = proplists:get_value(priv_dir, Config0),

    CompileOpts = [{outdir, PrivDir}, debug_info, beam_debug_info],

    TestSupportModule = Group,
    SrcFileName = filename:join(DataDir, atom_to_list(TestSupportModule) ++ ".erl"),
    Config1 =
        case filelib:is_file(SrcFileName) of
            false ->
                Config0;
            true ->
                {ok, _} = compile:file(SrcFileName, CompileOpts),
                BinFileName = filename:join(PrivDir, atom_to_list(TestSupportModule)),
                {module, TestSupportModule} = code:load_abs(BinFileName),
                [{erl_source, SrcFileName} | Config0]
        end,

    Config1.

end_per_group(Group, _Config) ->
    TestSupportModule = Group,
    case code:is_loaded(TestSupportModule) of
        false ->
            ok;
        {file, _} ->
            true = code:delete(TestSupportModule),
            code:purge(TestSupportModule)
    end,
    ok.

init_per_testcase(_Case, Config) ->
    ok = edb:attach(#{node => node()}),
    edb_test_support:start_event_collector(),
    ExcludedByDefault = edb:excluded_processes(),
    AmbientTestSupportProcsSpec = [
        {proc, Pid}
     || Pid <- erlang:processes(),
        not maps:is_key(Pid, ExcludedByDefault)
    ],
    edb:exclude_processes(AmbientTestSupportProcsSpec),
    Config.

%% erlfmt:ignore
end_per_testcase(_Case, _Config) ->
    edb_test_support:stop_event_collector(),
    try
        ok = edb:terminate()
    catch
        error:not_attached -> ok
    end,
    application:stop(dummy_app_1), % @oss-only
    application:stop(dummy_app_2), % @oss-only
    ok.

%% ------------------------------------------------------------------
%% Common macros
%% ------------------------------------------------------------------
-define(expectReceive(Expected), begin
    (fun() ->
        receive
            __Actual__ = Expected -> __Actual__
        after 2_000 ->
            receive
                __Actual__ = Expected ->
                    __Actual__;
                __NextMessage__ ->
                    error({timeout_receiving, ??Expected, {next_message, __NextMessage__}})
            after 0 ->
                error({timeout_receiving, ??Expected, nothing_received})
            end
        end
    end)()
end).

-define(ASSERT_NOTHING_ELSE_RECEIVED(),
    (fun() ->
        receive
            __Unexpected__ ->
                __Msg__ = io_lib:format(
                    "Received unexpected ~p",
                    [__Unexpected__]
                ),
                ?assert(false, lists:flatten(__Msg__))
        after 0 ->
            ok
        end
    end)()
).

% ------------------------------------------------------------------
% Test cases for test_subscriptions fixture
% ------------------------------------------------------------------

-define(ASSERT_RECEIVED_EDB_EVENT(Subscription, Event), begin
    ?expectReceive({edb_event, Subscription, Event})
end).

test_can_subscribe_and_unsubscribe(_Config) ->
    {ok, Subscription1} = edb:subscribe(),
    {ok, Subscription2} = edb:subscribe(),

    {ok, SyncRef1} = edb:send_sync_event(Subscription1),
    ?ASSERT_RECEIVED_EDB_EVENT(Subscription1, {sync, SyncRef1}),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    {ok, SyncRef2} = edb:send_sync_event(Subscription2),
    ?ASSERT_RECEIVED_EDB_EVENT(Subscription2, {sync, SyncRef2}),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    ok = edb:unsubscribe(Subscription1),
    ?ASSERT_RECEIVED_EDB_EVENT(Subscription1, unsubscribed),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    {error, unknown_subscription} = edb:send_sync_event(Subscription1),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    {ok, SyncRef3} = edb:send_sync_event(Subscription2),
    ?ASSERT_RECEIVED_EDB_EVENT(Subscription2, {sync, SyncRef3}),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),
    ok.

test_terminated_event_is_sent(_Config) ->
    {ok, Subscription} = edb:subscribe(),

    % Sanity-check: nothing sent before stopping the edb_server
    {ok, SyncRef} = edb:send_sync_event(Subscription),
    ?ASSERT_RECEIVED_EDB_EVENT(Subscription, {sync, SyncRef}),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    edb:terminate(),
    ?ASSERT_RECEIVED_EDB_EVENT(Subscription, {terminated, normal}),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    ok.

%% ------------------------------------------------------------------
%% Test cases for test_pause fixture
%% ------------------------------------------------------------------
test_pause_pauses(_Config) ->
    % Spawn a process that will run in a loop, sending us messages to sync
    Me = self(),
    Pid = erlang:spawn(test_pause, go, [Me, 0]),

    {_, Ref, _} = ?expectReceive({Pid, _, 0}),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Sanity-check: process currently waiting
    ?assertEqual({status, waiting}, erlang:process_info(Pid, status)),

    % Pause the VM
    ok = edb:pause(),

    % Process is now suspended
    ?assertEqual({status, suspended}, erlang:process_info(Pid, status)),

    % The process won't continue running even if "unblocked"
    Pid ! {continue, Ref},
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    {ok, resumed} = edb:continue(),

    % The process continues running
    {_, _Ref2, _} = ?expectReceive({Pid, _, 1}),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),
    ?assertEqual({status, waiting}, erlang:process_info(Pid, status)),

    % Check the events delivered
    ?assertEqual(
        [
            {paused, pause},
            {resumed, {continue, all}}
        ],
        edb_test_support:collected_events()
    ),
    ok.

test_pause_is_idempotent(_Config) ->
    % Spawn a process that will run in a loop, sending us messages to sync
    Me = self(),
    Pid = erlang:spawn(test_pause, go, [Me, 0]),

    % Call pause multiple times
    ok = edb:pause(),
    ok = edb:pause(),
    ok = edb:pause(),
    ok = edb:pause(),
    ok = edb:pause(),

    % Process is still suspended
    ?assertEqual({status, suspended}, erlang:process_info(Pid, status)),

    {ok, resumed} = edb:continue(),

    % We only sent the paused event once
    ?assertEqual(
        [
            {paused, pause},
            {resumed, {continue, all}}
        ],
        edb_test_support:collected_events()
    ),
    ok.

%% ------------------------------------------------------------------
%% Test cases for test_breakpoints fixture
%% ------------------------------------------------------------------

-define(ASSERT_SYNC_RECEIVED_FROM_LINE(ExpectedLine, Pid),
    (fun() ->
        receive
            {sync, Pid, __ActualLine__} ->
                ?assertEqual(ExpectedLine, __ActualLine__)
        after 2_000 ->
            __Msg__ = io_lib:format(
                "Timeout waiting for sync for line ~p",
                [ExpectedLine]
            ),
            ?assert(false, lists:flatten(__Msg__))
        end
    end)()
).

test_wait_waits_for_breakpoint_hit(_Config) ->
    % We set a breakpoint on a line of the test_breakpoints module.
    ok = edb:add_breakpoint(test_breakpoints, 8),

    % We spawn a process that will go through that line.
    Me = self(),
    % elp:ignore W0017 (undefined_function) - Module exists in test data
    Pid = erlang:spawn(fun() -> test_breakpoints:go(Me) end),

    % We call edb:wait(), blocking until the bp is hit
    {ok, paused} = edb:wait(),

    % We ensure the process is suspended, in the line we expect,
    % and that we only saw the side-effects of the lines prior to
    % the breakpoint being hit
    ?assertEqual({status, suspended}, erlang:process_info(Pid, status)),
    ?assertEqual(
        #{Pid => #{module => test_breakpoints, line => 8}},
        edb:get_breakpoints_hit()
    ),
    ?ASSERT_SYNC_RECEIVED_FROM_LINE(6, Pid),
    ?ASSERT_SYNC_RECEIVED_FROM_LINE(7, Pid),
    % stopped before sync on line 8
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Check the events delivered
    ?assertEqual(
        [
            {paused, {breakpoint, Pid, {test_breakpoints, go, 1}, {line, 8}}}
        ],
        edb_test_support:collected_events()
    ),
    ok.

test_continue_continues(_Config) ->
    % Initially, can continue() even while not paused, but nothing happens
    {ok, not_paused} = edb:continue(),

    % We set a breakpoint on two lines of the test_breakpoints module.
    ok = edb:add_breakpoint(test_breakpoints, 7),
    ok = edb:add_breakpoint(test_breakpoints, 8),

    % We spawn a process that will go through those lines.
    Me = self(),
    % elp:ignore W0017 (undefined_function) - Module exists in test data
    Pid = erlang:spawn(fun() -> test_breakpoints:go(Me) end),

    % We wait for the first breakpoint to be hit
    {ok, paused} = edb:wait(),

    % Sanity check: process hit the first bp, and we saw the right side-effects
    ?assertEqual(
        #{Pid => #{module => test_breakpoints, line => 7}},
        edb:get_breakpoints_hit()
    ),
    ?ASSERT_SYNC_RECEIVED_FROM_LINE(6, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % We call continue()
    {ok, resumed} = edb:continue(),

    % We now sit and wait again
    {ok, paused} = edb:wait(),

    % We ensure the process is suspended, in the second breakpoint,
    % and we saw the remaining side-effects
    ?assertEqual({status, suspended}, erlang:process_info(Pid, status)),
    ?assertEqual(
        #{Pid => #{module => test_breakpoints, line => 8}},
        edb:get_breakpoints_hit()
    ),
    ?ASSERT_SYNC_RECEIVED_FROM_LINE(7, Pid),
    % paused before sync on line 8
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Check the events delivered
    ?assertEqual(
        [
            {paused, {breakpoint, Pid, {test_breakpoints, go, 1}, {line, 7}}},

            {resumed, {continue, all}},

            {paused, {breakpoint, Pid, {test_breakpoints, go, 1}, {line, 8}}}
        ],
        edb_test_support:collected_events()
    ),
    ok.

test_hitting_a_breakpoint_suspends_other_processes(_Config) ->
    Me = self(),

    % We want a couple of ambient processes.
    AmbientPid1 = spawn_idle_proc(),
    AmbientPid2 = spawn_idle_proc(),
    AmbientPid3 = spawn_idle_proc(),

    % We set a breakpoint on a line of the test_breakpoints module.
    ok = edb:add_breakpoint(test_breakpoints, 14),

    % We spawn a process that will go through that line.
    % elp:ignore W0017 (undefined_function) - Module exists in test data
    Pid = erlang:spawn(fun() -> test_breakpoints:do_stuff_and_wait(Me) end),

    % We call edb:wait(), blocking until the bp is hit
    {ok, paused} = edb:wait(),

    % All newly created processes, get suspended
    ?assertEqual({status, suspended}, erlang:process_info(Pid, status)),
    ?assertEqual({status, suspended}, erlang:process_info(AmbientPid1, status)),
    ?assertEqual({status, suspended}, erlang:process_info(AmbientPid2, status)),
    ?assertEqual({status, suspended}, erlang:process_info(AmbientPid3, status)),

    % We continue, and sync
    {ok, resumed} = edb:continue(),
    ?ASSERT_SYNC_RECEIVED_FROM_LINE(14, Pid),

    % No process is now suspended
    ?assertMatch({status, S} when S =:= running orelse S =:= waiting, erlang:process_info(Pid, status)),
    ?assertEqual({status, waiting}, erlang:process_info(AmbientPid1, status)),
    ?assertEqual({status, waiting}, erlang:process_info(AmbientPid2, status)),
    ?assertEqual({status, waiting}, erlang:process_info(AmbientPid3, status)),

    % Check the events delivered
    ?assertEqual(
        [
            {paused, {breakpoint, Pid, {test_breakpoints, do_stuff_and_wait, 1}, {line, 14}}},

            {resumed, {continue, all}}
        ],
        edb_test_support:collected_events()
    ),
    ok.

test_processes_reports_running_and_paused_processes(_Config) ->
    Me = self(),

    % We want a couple of ambient processes.
    AmbientPid1 = spawn_idle_proc(),
    AmbientPid2 = spawn_idle_proc(),
    AmbientPid3 = spawn_idle_proc(),

    % We set a breakpoint on a line of the test_breakpoints module.
    ok = edb:add_breakpoint(test_breakpoints, 14),

    % Initially, ambient processes are reported as running
    ?assertMatch(
        #{
            AmbientPid1 := #{
                status := running,
                parent := Me,
                current_fun := {?MODULE, wait_for_any_message, 0}
            },
            AmbientPid2 := #{
                status := running,
                parent := Me,
                current_fun := {?MODULE, wait_for_any_message, 0}
            },
            AmbientPid3 := #{
                status := running,
                parent := Me,
                current_fun := {?MODULE, wait_for_any_message, 0}
            }
        },
        maps:with(
            [AmbientPid1, AmbientPid2, AmbientPid3],
            edb:processes()
        )
    ),

    % edb:process_info() agrees with edb:processes()
    ProcessesResult0 = edb:processes(),
    ?assertEqual(
        ProcessesResult0,
        #{Pid => Info || Pid := _ <- ProcessesResult0, {ok, Info} <- [edb:process_info(Pid)]}
    ),

    % We spawn a process that will go through that line.
    % elp:ignore W0017 (undefined_function) - Module exists in test data
    DebugeePid = erlang:spawn(fun() -> test_breakpoints:do_stuff_and_wait(Me) end),

    % We call edb:wait(), blocking until the bp is hit
    {ok, paused} = edb:wait(),

    % Processes are now reported as paused / on a breakpoint
    ?assertMatch(
        #{
            DebugeePid := #{
                status := breakpoint,
                parent := Me,
                current_fun := {_, _, _},
                current_bp := {line, 14}
            },
            AmbientPid1 := #{
                status := paused,
                parent := Me,
                current_fun := {?MODULE, wait_for_any_message, 0}
            },
            AmbientPid2 := #{
                status := paused,
                parent := Me,
                current_fun := {?MODULE, wait_for_any_message, 0}
            },
            AmbientPid3 := #{
                status := paused,
                parent := Me,
                current_fun := {?MODULE, wait_for_any_message, 0}
            }
        },
        maps:with(
            [DebugeePid, AmbientPid1, AmbientPid2, AmbientPid3],
            edb:processes()
        )
    ),

    % edb:process_info() still agrees with edb:processes()
    ProcessesResult1 = edb:processes(),
    ?assertEqual(
        ProcessesResult1,
        #{Pid => Info || Pid := _ <- ProcessesResult1, {ok, Info} <- [edb:process_info(Pid)]}
    ),

    % All processes are now actually suspended
    [
        ?assertEqual(
            {Proc, {status, suspended}},
            {Proc, erlang:process_info(Proc, status)}
        )
     || Proc := _ <- edb:processes()
    ],

    % We continue
    {ok, resumed} = edb:continue(),

    % Again, everything reported as running
    ?assertMatch(
        #{
            DebugeePid := #{
                status := running,
                parent := Me,
                current_fun := {_, _, _}
            },
            AmbientPid1 := #{
                status := running,
                parent := Me,
                current_fun := {?MODULE, wait_for_any_message, 0}
            },
            AmbientPid2 := #{
                status := running,
                parent := Me,
                current_fun := {?MODULE, wait_for_any_message, 0}
            },
            AmbientPid3 := #{
                status := running,
                parent := Me,
                current_fun := {?MODULE, wait_for_any_message, 0}
            }
        },
        maps:with(
            [DebugeePid, AmbientPid1, AmbientPid2, AmbientPid3],
            edb:processes()
        )
    ),

    % Check the events delivered
    ?assertEqual(
        [
            {paused, {breakpoint, DebugeePid, {test_breakpoints, do_stuff_and_wait, 1}, {line, 14}}},
            {resumed, {continue, all}}
        ],
        edb_test_support:collected_events()
    ),
    ok.

test_excluded_processes_reports_excluded_processes(_Config) ->
    Me = self(),

    % We want an ambient processes to be paused
    UnrelatedPid = spawn_idle_proc(),

    % We want a process explicitly excluded by pid
    ExcludedPid = spawn_idle_proc(),
    ok = edb:exclude_processes([{proc, ExcludedPid}]),

    % We also want a process excluded by registered name
    ok = edb:exclude_processes([{proc, some_named_proc}]),
    NameablePid1 = spawn_idle_proc(),
    NameablePid2 = spawn_idle_proc(),
    erlang:register(some_named_proc, NameablePid1),

    % We also want to exclude an application
    ok = application:start(dummy_app_1),
    ok = application:start(dummy_app_2),
    {DummyApp1Pid, DummyApp1SupPid} = {whereis(dummy_app_1), whereis(dummy_app_1_sup)},
    {DummyApp2Pid, DummyApp2SupPid} = {whereis(dummy_app_2), whereis(dummy_app_2_sup)},

    ok = edb:exclude_processes([{application, dummy_app_1}]),

    % Subscribed processes are excluded
    SubscribedPid = erlang:spawn(fun() ->
        edb:subscribe(),
        receive
        after infinity -> ok
        end
    end),

    % Automatically excluded processes are reported

    ?assertMatch(
        #{
            Me := #{
                parent := _,
                current_fun := _,
                reason := [excluded_pid],
                message_queue_len := _
            }
        },
        maps:with([Me], edb:excluded_processes())
    ),

    KernelSupPid = erlang:whereis(kernel_sup),
    ?assertMatch(
        #{
            KernelSupPid := #{
                parent := _,
                current_fun := _,
                message_queue_len := _,
                registered_name := kernel_sup,
                application := kernel,
                reason := [excluded_application]
            }
        },
        maps:with([KernelSupPid], edb:excluded_processes())
    ),

    InitPid = erlang:whereis(init),
    ?assertMatch(
        #{
            InitPid := #{
                current_fun := _,
                registered_name := init,
                reason := [system_component]
            }
        },
        maps:with([InitPid], edb:excluded_processes())
    ),

    ?assertMatch(
        #{
            SubscribedPid := #{
                current_fun := _,
                reason := [debugger_component]
            }
        },
        maps:with([SubscribedPid], edb:excluded_processes())
    ),

    % Manually excluded processes are reported

    IdleProcMFA = {?MODULE, wait_for_any_message, 0},
    Info = #{parent => Me, current_fun => IdleProcMFA, message_queue_len => 0},

    ?assertEqual(
        #{ExcludedPid => Info#{reason => [excluded_pid]}},
        maps:with([ExcludedPid], edb:excluded_processes())
    ),

    ?assertEqual(
        #{
            NameablePid1 => Info#{
                reason => [excluded_regname],
                registered_name => some_named_proc
            }
        },
        maps:with([NameablePid1], edb:excluded_processes())
    ),

    ?assertMatch(
        #{
            DummyApp1SupPid := #{
                parent := SupParentPid,
                application := dummy_app_1,
                reason := [excluded_application],
                registered_name := dummy_app_1_sup
            },

            DummyApp1Pid := #{
                application := dummy_app_1,
                % name is used if available
                parent := dummy_app_1_sup,
                reason := [excluded_application],
                registered_name := dummy_app_1
            }
        } when is_pid(SupParentPid),
        maps:with([DummyApp1Pid, DummyApp1SupPid], edb:excluded_processes())
    ),

    % Non-excluded processes are not reported

    ?assertMatch(
        #{},
        maps:with(
            [UnrelatedPid, NameablePid2, DummyApp2Pid, DummyApp2SupPid],
            edb:excluded_processes()
        )
    ),

    % All reasons for excluding will be reported

    ok = edb:exclude_process(DummyApp1Pid),

    ?assertMatch(
        #{DummyApp1Pid := #{reason := [excluded_application, excluded_pid]}},
        maps:with([DummyApp1Pid], edb:excluded_processes())
    ),

    % Registered name is dynamically converted to pid
    ?assertEqual(
        #{
            NameablePid1 => Info#{
                reason => [excluded_regname],
                registered_name => some_named_proc
            }
        },
        maps:with([NameablePid1, NameablePid2], edb:excluded_processes())
    ),

    erlang:unregister(some_named_proc),
    ?assertEqual(
        #{},
        maps:with([NameablePid1, NameablePid2], edb:excluded_processes())
    ),

    erlang:register(some_named_proc, NameablePid2),
    ?assertEqual(
        #{
            NameablePid2 => Info#{
                reason => [excluded_regname],
                registered_name => some_named_proc
            }
        },
        maps:with([NameablePid1, NameablePid2], edb:excluded_processes())
    ),

    % Check the events delivered
    ?assertEqual(
        [],
        edb_test_support:collected_events()
    ),
    ok.

test_excluded_processes_dont_hit_breakpoints(_Config) ->
    % Set a breakpoint in test_breakpoints:do_stuff_and_wait/1
    ok = edb:add_breakpoint(test_breakpoints, 14),

    TC = self(),

    % Call it on a normal process and one that is excluded from debugging.
    % We add a sync to ensure the process is excluded before it tries to hit the breakpoint.
    Action = fun() ->
        receive
            gogogo -> erlang:apply(test_breakpoints, do_stuff_and_wait, [TC])
        end
    end,

    NormalPid = erlang:spawn(Action),
    ExcludedPid = erlang:spawn(Action),
    edb:exclude_processes([{proc, ExcludedPid}]),

    [P ! gogogo || P <- [NormalPid, ExcludedPid]],

    % Sanity check: only the expected pids are excluded
    ?assertNotMatch(#{NormalPid := _}, edb:excluded_processes()),
    ?assertMatch(#{ExcludedPid := _}, edb:excluded_processes()),

    % Wait for the BP
    {ok, paused} = edb:wait(),

    % The breakpoint was not hit for the excluded pid and hit on the normal one
    ?ASSERT_SYNC_RECEIVED_FROM_LINE(14, ExcludedPid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Check the events delivered
    ?assertEqual(
        [
            {paused, {breakpoint, NormalPid, {test_breakpoints, do_stuff_and_wait, 1}, {line, 14}}}
        ],
        edb_test_support:collected_events()
    ),
    ok.

test_excluding_a_process_makes_it_resume(_Config) ->
    % Set a breakpoint in test_breakpoints:go/1
    ok = edb:add_breakpoint(test_breakpoints, 6),

    % Start two processes
    Pid1 = erlang:spawn(test_breakpoints, go, [self()]),
    Pid2 = erlang:spawn(test_breakpoints, go, [self()]),

    {ok, paused} = edb:wait(),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    edb:exclude_process(Pid1),
    [?ASSERT_SYNC_RECEIVED_FROM_LINE(L, Pid1) || L <- [6, 7, 8, 9]],
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    edb:exclude_process(Pid2),
    [?ASSERT_SYNC_RECEIVED_FROM_LINE(L, Pid2) || L <- [6, 7, 8, 9]],
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Check the events delivered (multiple possible cases due to non-determinism)
    case edb_test_support:collected_events() of
        [
            {paused, {breakpoint, PidBp, {test_breakpoints, go, 1}, {line, 6}}},

            {resumed, {excluded, ExcludedMap1}},
            {resumed, {excluded, ExclidedMap2}}
        ] when
            (PidBp =:= Pid1 orelse PidBp =:= Pid2) andalso
                ((ExcludedMap1 =:= #{Pid1 => []} andalso ExclidedMap2 =:= #{Pid2 => []}) orelse
                    (ExcludedMap1 =:= #{Pid2 => []} andalso ExclidedMap2 =:= #{Pid1 => []}))
        ->
            ok;
        [
            {paused, {breakpoint, PidBp1, {test_breakpoints, go, 1}, {line, 6}}},
            {paused, {breakpoint, PidBp2, {test_breakpoints, go, 1}, {line, 6}}},

            {resumed, {excluded, ExcludedMap1}},
            {resumed, {excluded, ExclidedMap2}}
        ] when
            ((PidBp1 =:= Pid1 andalso PidBp2 =:= Pid2) orelse (PidBp1 =:= Pid2 andalso PidBp2 =:= Pid1)) andalso
                ((ExcludedMap1 =:= #{Pid1 => []} andalso ExclidedMap2 =:= #{Pid2 => []}) orelse
                    (ExcludedMap1 =:= #{Pid2 => []} andalso ExclidedMap2 =:= #{Pid1 => []}))
        ->
            ok;
        Actual ->
            OneExpectedCase = [
                {paused, {breakpoint, Pid1, {test_breakpoints, go, 1}, {line, 6}}},
                {paused, {breakpoint, Pid2, {test_breakpoints, go, 1}, {line, 6}}},

                {resumed, {excluded, #{Pid1 => []}}},
                {resumed, {excluded, #{Pid2 => []}}}
            ],
            % This will fail, but the error message will be more useful
            ?assertEqual(
                OneExpectedCase,
                Actual
            )
    end,
    ok.

test_can_override_excluded_processes_by_other_reasons(_Config) ->
    edb:exclude_processes([{application, dummy_app_1}]),
    application:start(dummy_app_1),
    {DummyApp1Pid, DummyApp1SupPid} = {whereis(dummy_app_1), whereis(dummy_app_1_sup)},

    SubscribedPid = erlang:spawn(fun() ->
        edb:subscribe(),
        receive
        after infinity -> ok
        end
    end),

    % Sanity check linked processes are excluded
    ?assertMatch(#{DummyApp1Pid := _}, edb:excluded_processes()),
    ?assertMatch(#{DummyApp1SupPid := _}, edb:excluded_processes()),
    ?assertMatch(#{SubscribedPid := _}, edb:excluded_processes()),

    % Except some of them
    edb:exclude_processes([{except, DummyApp1Pid}, {except, SubscribedPid}]),

    ?assertNotMatch(#{DummyApp1Pid := _}, edb:excluded_processes()),
    ?assertMatch(#{DummyApp1SupPid := _}, edb:excluded_processes()),
    ?assertNotMatch(#{SubscribedPid := _}, edb:excluded_processes()),

    % Remove one exception
    edb:unexclude_processes([{except, DummyApp1Pid}]),

    ?assertMatch(#{DummyApp1Pid := _}, edb:excluded_processes()),
    ?assertMatch(#{DummyApp1SupPid := _}, edb:excluded_processes()),
    ?assertNotMatch(#{SubscribedPid := _}, edb:excluded_processes()),

    % Check the events delivered
    ?assertEqual(
        [],
        edb_test_support:collected_events()
    ),
    ok.

test_can_reinclude_previously_excluded_processes(_Config) ->
    Pid1 = spawn_idle_proc(),
    Pid2 = spawn_idle_proc(),
    edb:exclude_processes([{proc, Pid1}, {proc, Pid2}]),

    % Sanity-check: processes current excluded
    ?assertMatch(#{Pid1 := _}, edb:excluded_processes()),
    ?assertMatch(#{Pid2 := _}, edb:excluded_processes()),

    % Reinclude only one of them
    edb:unexclude_processes([{proc, Pid1}]),

    ?assertNotMatch(#{Pid1 := _}, edb:excluded_processes()),
    ?assertMatch(#{Pid2 := _}, edb:excluded_processes()),

    % Check the events delivered
    ?assertEqual(
        [],
        edb_test_support:collected_events()
    ),
    ok.

test_including_a_process_can_suspend_it_immediately(_Config) ->
    % Set a breakpoint in test_breakpoints:go/1
    ok = edb:add_breakpoint(test_breakpoints, 6),

    Pid1 = spawn_idle_proc(),
    Pid2 = spawn_idle_proc(),
    edb:exclude_processes([{proc, Pid1}, {proc, Pid2}]),

    % Make a process hit the breakpoint
    Pid3 = erlang:spawn(test_breakpoints, go, [self()]),
    {ok, paused} = edb:wait(),

    % Sanity-check: excluded processes not currently suspended
    ?assertEqual({status, waiting}, erlang:process_info(Pid1, status)),
    ?assertEqual({status, waiting}, erlang:process_info(Pid2, status)),

    % Include one of them
    edb:unexclude_processes([{proc, Pid1}]),

    % The included process got suspended
    ?assertEqual({status, suspended}, erlang:process_info(Pid1, status)),
    ?assertEqual({status, waiting}, erlang:process_info(Pid2, status)),

    % Check the events delivered
    ?assertEqual(
        [
            {paused, {breakpoint, Pid3, {test_breakpoints, go, 1}, {line, 6}}}
        ],
        edb_test_support:collected_events()
    ),
    ok.

test_clear_breakpoint_clears_breakpoints(_Config) ->
    % We set a breakpoint on two lines of the test_breakpoints module.
    ok = edb:add_breakpoint(test_breakpoints, 7),
    ok = edb:add_breakpoint(test_breakpoints, 8),

    % We now clear the first breakpoint
    ok = edb:clear_breakpoint(test_breakpoints, 7),

    % We spawn a process that will go through those lines.
    Pid = erlang:spawn(test_breakpoints, go, [self()]),

    % We wait for the first breakpoint to be hit
    {ok, paused} = edb:wait(),

    % We expect to be in line 8, since the breakpoint on line 7
    % was removed
    ?assertEqual(
        #{Pid => #{module => test_breakpoints, line => 8}},
        edb:get_breakpoints_hit()
    ),
    ?ASSERT_SYNC_RECEIVED_FROM_LINE(6, Pid),
    ?ASSERT_SYNC_RECEIVED_FROM_LINE(7, Pid),
    % paused before sync on line 8
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Check the events delivered
    ?assertEqual(
        [
            {paused, {breakpoint, Pid, {test_breakpoints, go, 1}, {line, 8}}}
        ],
        edb_test_support:collected_events()
    ),
    ok.

test_clear_breakpoints_clears_all_breakpoints(_Config) ->
    % We set a breakpoint on two lines of the test_breakpoints module.
    ok = edb:add_breakpoint(test_breakpoints, 6),
    ok = edb:add_breakpoint(test_breakpoints, 7),
    ok = edb:add_breakpoint(test_breakpoints, 8),
    ok = edb:add_breakpoint(test_breakpoints, 9),

    % Sanity check that the breakpoints are there
    ?assertEqual(
        #{
            test_breakpoints =>
                [
                    #{line => 6, module => test_breakpoints},
                    #{line => 7, module => test_breakpoints},
                    #{line => 8, module => test_breakpoints},
                    #{line => 9, module => test_breakpoints}
                ]
        },
        edb:get_breakpoints()
    ),

    ok = edb:clear_breakpoints(test_breakpoints),

    ?assertEqual(
        #{},
        edb:get_breakpoints()
    ),

    % We add a breakpoint on a later line
    ok = edb:add_breakpoint(test_breakpoints, 10),
    % Sanity check that the breakpoints are there
    ?assertEqual(
        #{
            test_breakpoints =>
                [
                    #{line => 10, module => test_breakpoints}
                ]
        },
        edb:get_breakpoints()
    ),

    % We spawn a process that will go through those lines.
    Pid = erlang:spawn(test_breakpoints, go, [self()]),
    {ok, paused} = edb:wait(),

    % We check that we only hit the later breakpoint
    ?assertEqual(
        #{Pid => #{line => 10, module => test_breakpoints}},
        edb:get_breakpoints_hit()
    ),

    ?ASSERT_SYNC_RECEIVED_FROM_LINE(6, Pid),
    ?ASSERT_SYNC_RECEIVED_FROM_LINE(7, Pid),
    ?ASSERT_SYNC_RECEIVED_FROM_LINE(8, Pid),
    ?ASSERT_SYNC_RECEIVED_FROM_LINE(9, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Check the events delivered
    ?assertEqual(
        [
            {paused, {breakpoint, Pid, {test_breakpoints, go, 1}, {line, 10}}}
        ],
        edb_test_support:collected_events()
    ),
    ok.

test_get_breakpoints_reports_current_set_breakpoints(_Config) ->
    % We set a breakpoint on several lines of the test_breakpoints module.
    % We don't set them in order
    ok = edb:add_breakpoint(test_breakpoints, 7),
    ok = edb:add_breakpoint(test_breakpoints, 6),
    ok = edb:add_breakpoint(test_breakpoints, 8),

    % We can see them with get_breakpoints(), theys show up in order
    ?assertEqual(
        #{
            test_breakpoints => [
                #{line => 6, module => test_breakpoints},
                #{line => 7, module => test_breakpoints},
                #{line => 8, module => test_breakpoints}
            ]
        },
        edb:get_breakpoints()
    ),

    % We remove one of the breakpoints
    ok = edb:clear_breakpoint(test_breakpoints, 7),

    % We no longer see it
    ?assertEqual(
        #{
            test_breakpoints => [
                #{line => 6, module => test_breakpoints},
                #{line => 8, module => test_breakpoints}
            ]
        },
        edb:get_breakpoints()
    ),

    % We remove another one
    ok = edb:clear_breakpoint(test_breakpoints, 8),

    % We no longer see it
    ?assertEqual(
        #{
            test_breakpoints => [
                #{line => 6, module => test_breakpoints}
            ]
        },
        edb:get_breakpoints()
    ),

    % We remove the last one
    ok = edb:clear_breakpoint(test_breakpoints, 6),

    % They are all gone
    ?assertEqual(
        #{},
        edb:get_breakpoints()
    ),

    % Check the events delivered
    ?assertEqual(
        [],
        edb_test_support:collected_events()
    ),
    ok.

%% ------------------------------------------------------------------
%% Test cases for test_step_over fixture
%% ------------------------------------------------------------------

test_step_over_goes_to_next_line(_Config) ->
    % Add a breakpoint to step from
    ok = edb:add_breakpoint(test_step_over, 20),

    % Spawn a process that will hit this breakpoint
    Pid = erlang:spawn(test_step_over, go, [self()]),
    {ok, paused} = edb:wait(),

    ?ASSERT_SYNC_RECEIVED_FROM_LINE(19, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Sanity check that we hit the breapoint
    ?assertEqual(
        #{Pid => #{line => 20, module => test_step_over}},
        edb:get_breakpoints_hit()
    ),

    % Define a function to step over on next line to avoid repetitions
    CheckStepOnLine = fun(NextLine) ->
        % Step over to reach next line
        ok = edb:step_over(Pid),
        {ok, paused} = edb:wait(),

        % Check that we stopped on the next line
        ?assertMatch(
            {ok, [#{mfa := {test_step_over, go, 1}, line := NextLine}]},
            edb:stack_frames(Pid)
        ),

        ?ASSERT_SYNC_RECEIVED_FROM_LINE(NextLine - 1, Pid),
        ?ASSERT_NOTHING_ELSE_RECEIVED(),

        % Stepping does not count as hitting a breakpoint
        ?assertEqual(
            #{},
            edb:get_breakpoints_hit()
        )
    end,

    CheckStepOnLine(21),
    CheckStepOnLine(22),
    CheckStepOnLine(23),

    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Check the events delivered
    ?assertEqual(
        [
            {paused, {breakpoint, Pid, {test_step_over, go, 1}, {line, 20}}},
            {resumed, {continue, all}},
            {paused, {step, Pid}},
            {resumed, {continue, all}},
            {paused, {step, Pid}},
            {resumed, {continue, all}},
            {paused, {step, Pid}}
        ],

        edb_test_support:collected_events()
    ),
    ok.

test_step_over_skips_same_name_fun_call(_Config) ->
    % Add a breakpoint to step from
    ok = edb:add_breakpoint(test_step_over, 44),

    % Spawn a process that will hit this breakpoint
    Pid = erlang:spawn(test_step_over, just_sync, [self(), unused_argument]),
    {ok, paused} = edb:wait(),

    % No sync received yet
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Sanity check that we hit the breapoint
    ?assertEqual(
        #{Pid => #{line => 44, module => test_step_over}},
        edb:get_breakpoints_hit()
    ),

    % Step over to reach next line
    ok = edb:step_over(Pid),
    {ok, paused} = edb:wait(),

    % We went through the call to just_sync/1
    ?ASSERT_SYNC_RECEIVED_FROM_LINE(39, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Check that we reached the next line of just_sync/2
    ?assertMatch(
        {ok, [#{mfa := {test_step_over, just_sync, 2}, line := 45}]},
        edb:stack_frames(Pid)
    ),

    % Check the events delivered
    ?assertEqual(
        [
            {paused, {breakpoint, Pid, {test_step_over, just_sync, 2}, {line, 44}}},
            {resumed, {continue, all}},
            {paused, {step, Pid}}
        ],

        edb_test_support:collected_events()
    ),
    ok.

test_step_over_fails_on_running_process(_Config) ->
    % Spawn a process that will loop forever without hitting any breakpoint
    Pid = erlang:spawn(test_step_over, cycle, [self(), left]),

    % Sanity check: no breakpoint should have been hit
    ?assertEqual(
        #{},
        edb:get_breakpoints_hit()
    ),

    % Try to step over to reach next line
    ?assertMatch({error, not_paused}, edb:step_over(Pid)),

    % Still no breakpoint hit
    ?assertEqual(
        #{},
        edb:get_breakpoints_hit()
    ),

    % Check the events delivered
    ?assertEqual(
        [],
        edb_test_support:collected_events()
    ),
    ok.

test_step_over_to_caller_on_return(_Config) ->
    % Add a breakpoint at the end of the callee just_sync/1
    ok = edb:add_breakpoint(test_step_over, 40),

    % Spawn a process that will hit this breakpoint through the caller just_sync/2
    Pid = erlang:spawn(test_step_over, just_sync, [self(), unused_argument]),
    {ok, paused} = edb:wait(),

    ?ASSERT_SYNC_RECEIVED_FROM_LINE(39, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Check that we reach the breakpoint location
    ?assertMatch(
        {ok, [#{mfa := {_, just_sync, 1}, line := 40} | _]},
        edb:stack_frames(Pid)
    ),

    % Step over to reach next line. This should take us to the caller just_sync/2
    ok = edb:step_over(Pid),
    {ok, paused} = edb:wait(),

    % Check that we stopped on the next line of just_sync/2
    ?assertMatch(
        {ok, [#{mfa := {_, just_sync, 2}, line := 45} | _]},
        edb:stack_frames(Pid)
    ),

    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Check the events delivered
    ?assertEqual(
        [
            {paused, {breakpoint, Pid, {test_step_over, just_sync, 1}, {line, 40}}},
            {resumed, {continue, all}},
            {paused, {step, Pid}}
        ],
        edb_test_support:collected_events()
    ),

    ok.

test_step_over_within_and_out_of_closure(_Config) ->
    % Add a breakpoint to step from, in the closure
    ok = edb:add_breakpoint(test_step_over, 54),

    % Spawn a process that will hit this breakpoint
    Pid = erlang:spawn(test_step_over, call_closure, [self()]),
    {ok, paused} = edb:wait(),

    ?ASSERT_SYNC_RECEIVED_FROM_LINE(51, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Sanity check that we hit the breakpoint
    ?assertEqual(
        #{Pid => #{line => 54, module => test_step_over}},
        edb:get_breakpoints_hit()
    ),

    % Check that we are inside the closure
    ?assertMatch(
        {ok, [
            #{mfa := {test_step_over, '-call_closure/1-fun-0-', 2}, line := 54},
            #{mfa := {test_step_over, call_closure, 1}, line := 53}
        ]},
        edb:stack_frames(Pid)
    ),

    % Step within the closure
    ok = edb:step_over(Pid),
    {ok, paused} = edb:wait(),

    ?assertMatch(
        {ok, [
            #{mfa := {test_step_over, '-call_closure/1-fun-0-', 2}, line := 55},
            #{mfa := {test_step_over, call_closure, 1}, line := 53}
        ]},
        edb:stack_frames(Pid)
    ),

    ?ASSERT_SYNC_RECEIVED_FROM_LINE(54, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Step over to reach next executable line -- after closure call
    ok = edb:step_over(Pid),
    {ok, paused} = edb:wait(),

    ?assertMatch(
        {ok, [
            #{mfa := {test_step_over, call_closure, 1}, line := 57}
        ]},
        edb:stack_frames(Pid)
    ),

    % Sanity check that we can still step over in the caller
    ok = edb:step_over(Pid),
    {ok, paused} = edb:wait(),

    ?assertMatch(
        {ok, [
            #{mfa := {test_step_over, call_closure, 1}, line := 58}
        ]},
        edb:stack_frames(Pid)
    ),

    ?ASSERT_SYNC_RECEIVED_FROM_LINE(57, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Check the events delivered
    ?assertEqual(
        [
            {paused, {breakpoint, Pid, {test_step_over, '-call_closure/1-fun-0-', 2}, {line, 54}}},
            {resumed, {continue, all}},
            {paused, {step, Pid}},
            {resumed, {continue, all}},
            {paused, {step, Pid}},
            {resumed, {continue, all}},
            {paused, {step, Pid}}
        ],
        edb_test_support:collected_events()
    ),

    ok.

test_step_over_within_and_out_of_external_closure(_Config) ->
    % Add a breakpoint to step from, in the external closure
    ok = edb:add_breakpoint(test_step_over, 71),

    % Spawn a process that will hit this breakpoint
    Pid = erlang:spawn(test_step_over, call_external_closure, [self()]),
    {ok, paused} = edb:wait(),

    ?ASSERT_SYNC_RECEIVED_FROM_LINE(62, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Sanity check that we hit the breakpoint
    ?assertEqual(
        #{Pid => #{line => 71, module => test_step_over}},
        edb:get_breakpoints_hit()
    ),

    % Check that we are inside the closure, called from call_external_closure
    % The closure-defining make_closure doesn't appear in the stack
    ?assertMatch(
        {ok, [
            #{mfa := {test_step_over, '-make_closure/1-fun-0-', 1}, line := 71},
            #{mfa := {test_step_over, call_external_closure, 1}, line := 64}
        ]},
        edb:stack_frames(Pid)
    ),

    % Step within the closure
    ok = edb:step_over(Pid),
    {ok, paused} = edb:wait(),

    ?assertMatch(
        {ok, [
            #{mfa := {test_step_over, '-make_closure/1-fun-0-', 1}, line := 72},
            #{mfa := {test_step_over, call_external_closure, 1}, line := 64}
        ]},
        edb:stack_frames(Pid)
    ),

    ?ASSERT_SYNC_RECEIVED_FROM_LINE(71, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Step over to reach next executable line -- after closure call, back in closure caller
    ok = edb:step_over(Pid),
    {ok, paused} = edb:wait(),

    ?assertMatch(
        {ok, [
            #{mfa := {test_step_over, call_external_closure, 1}, line := 65}
        ]},
        edb:stack_frames(Pid)
    ),

    % Sanity check that we can still step over in the caller
    ok = edb:step_over(Pid),
    {ok, paused} = edb:wait(),

    ?assertMatch(
        {ok, [
            #{mfa := {test_step_over, call_external_closure, 1}, line := 66}
        ]},
        edb:stack_frames(Pid)
    ),

    ?ASSERT_SYNC_RECEIVED_FROM_LINE(65, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Check the events delivered
    ?assertEqual(
        [
            {paused, {breakpoint, Pid, {test_step_over, '-make_closure/1-fun-0-', 1}, {line, 71}}},
            {resumed, {continue, all}},
            {paused, {step, Pid}},
            {resumed, {continue, all}},
            {paused, {step, Pid}},
            {resumed, {continue, all}},
            {paused, {step, Pid}}
        ],
        edb_test_support:collected_events()
    ),

    ok.

test_step_over_into_local_handler(_Config) ->
    % Add a breakpoint to step from, before calling the chain of exception raises
    ok = edb:add_breakpoint(test_step_over, 79),

    % Spawn a process that will hit this breakpoint
    Pid = erlang:spawn(test_step_over, catch_exception, [self()]),
    {ok, paused} = edb:wait(),

    ?ASSERT_SYNC_RECEIVED_FROM_LINE(77, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Sanity check that we end on the expected program point
    ?assertMatch(
        {ok, [
            #{mfa := {test_step_over, catch_exception, 1}, line := 79}
        ]},
        edb:stack_frames(Pid)
    ),

    % Step over, that will raise the exception
    ok = edb:step_over(Pid),
    {ok, paused} = edb:wait(),

    ?ASSERT_SYNC_RECEIVED_FROM_LINE(88, Pid),
    ?ASSERT_SYNC_RECEIVED_FROM_LINE(94, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Check that we end up on the handler
    ?assertMatch(
        {ok, [
            #{mfa := {test_step_over, catch_exception, 1}, line := 82}
        ]},
        edb:stack_frames(Pid)
    ),

    % Sanity check that we can continue stepping over
    ok = edb:step_over(Pid),
    ?ASSERT_SYNC_RECEIVED_FROM_LINE(82, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Check the events delivered
    ?assertEqual(
        [
            {paused, {breakpoint, Pid, {test_step_over, catch_exception, 1}, {line, 79}}},
            {resumed, {continue, all}},
            {paused, {step, Pid}},
            {resumed, {continue, all}},
            {paused, {step, Pid}}
        ],
        edb_test_support:collected_events()
    ),

    ok.

test_step_over_into_caller_handler(_Config) ->
    % Add a breakpoint to step from, just before raising an exception
    ok = edb:add_breakpoint(test_step_over, 95),

    % Spawn a process that will hit this breakpoint
    Pid = erlang:spawn(test_step_over, catch_exception, [self()]),
    {ok, paused} = edb:wait(),

    ?ASSERT_SYNC_RECEIVED_FROM_LINE(77, Pid),
    ?ASSERT_SYNC_RECEIVED_FROM_LINE(88, Pid),
    ?ASSERT_SYNC_RECEIVED_FROM_LINE(94, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Sanity check that we end on the expected program point
    ?assertMatch(
        {ok, [
            #{mfa := {test_step_over, raise_exception, 1}, line := 95},
            #{mfa := {test_step_over, indirect_raise_exception, 1}, line := 89},
            #{mfa := {test_step_over, catch_exception, 1}, line := 79}
        ]},
        edb:stack_frames(Pid)
    ),

    % Step over, that will raise the exception
    ok = edb:step_over(Pid),
    {ok, paused} = edb:wait(),

    % Check that we end up on the handler
    ?assertMatch(
        {ok, [
            #{mfa := {test_step_over, catch_exception, 1}, line := 82}
        ]},
        edb:stack_frames(Pid)
    ),

    % Sanity check that we can continue stepping
    ok = edb:step_over(Pid),
    ?ASSERT_SYNC_RECEIVED_FROM_LINE(82, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Check the events delivered
    ?assertEqual(
        [
            {paused, {breakpoint, Pid, {test_step_over, raise_exception, 1}, {line, 95}}},
            {resumed, {continue, all}},
            {paused, {step, Pid}},
            {resumed, {continue, all}},
            {paused, {step, Pid}}
        ],
        edb_test_support:collected_events()
    ),

    ok.

test_step_over_progresses_from_breakpoint(_Config) ->
    % We test that a succession of steps isn't impedimented by the presence of breakpoints

    % Add a breakpoint to start stepping from
    ok = edb:add_breakpoint(test_step_over, 20),

    % Add a breakpoint that will be "stepped on and from"
    ok = edb:add_breakpoint(test_step_over, 21),

    % Spawn a process that will hit the first breakpoint
    Pid = erlang:spawn(test_step_over, go, [self()]),
    {ok, paused} = edb:wait(),

    ?ASSERT_SYNC_RECEIVED_FROM_LINE(19, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Sanity check that we hit the breakpoint
    ?assertEqual(
        #{Pid => #{line => 20, module => test_step_over}},
        edb:get_breakpoints_hit()
    ),

    % Now step onto the next breakpoint
    ok = edb:step_over(Pid),
    {ok, paused} = edb:wait(),

    ?ASSERT_SYNC_RECEIVED_FROM_LINE(20, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % "Breakpoint hit wins": if we step on a breakpoint then we consider having hit it
    ?assertEqual(
        #{Pid => #{line => 21, module => test_step_over}},
        edb:get_breakpoints_hit()
    ),

    % Step over from this breakpoint will keep progressing
    ok = edb:step_over(Pid),
    {ok, paused} = edb:wait(),

    ?ASSERT_SYNC_RECEIVED_FROM_LINE(21, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Check that we end up on the line after
    ?assertMatch(
        {ok, [
            #{mfa := {test_step_over, go, 1}, line := 22}
        ]},
        edb:stack_frames(Pid)
    ),

    % Check the events delivered
    % In particular we should register a bp hit event after the step onto line 21
    ?assertEqual(
        [
            {paused, {breakpoint, Pid, {test_step_over, go, 1}, {line, 20}}},
            {resumed, {continue, all}},
            {paused, {breakpoint, Pid, {test_step_over, go, 1}, {line, 21}}},
            {resumed, {continue, all}},
            {paused, {step, Pid}}
        ],
        edb_test_support:collected_events()
    ),

    ok.

test_breakpoint_consumes_step(_Config) ->
    % Add a breakpoint to start stepping from
    ok = edb:add_breakpoint(test_step_over, 20),

    % Add a breakpoint that will be "stepped on"
    ok = edb:add_breakpoint(test_step_over, 21),

    % Spawn a process that will hit the first breakpoint
    Pid = erlang:spawn(test_step_over, go, [self()]),
    {ok, paused} = edb:wait(),

    ?ASSERT_SYNC_RECEIVED_FROM_LINE(19, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Sanity check that we hit the breakpoint
    ?assertEqual(
        #{Pid => #{line => 20, module => test_step_over}},
        edb:get_breakpoints_hit()
    ),

    % Now step onto the next breakpoint
    ok = edb:step_over(Pid),
    {ok, paused} = edb:wait(),

    ?ASSERT_SYNC_RECEIVED_FROM_LINE(20, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % "Breakpoint hit wins": if we step on a breakpoint then we consider having hit it
    ?assertEqual(
        #{Pid => #{line => 21, module => test_step_over}},
        edb:get_breakpoints_hit()
    ),

    % Step has been consumed: if we continue from this breakpoint we don't stop again
    {ok, resumed} = edb:continue(),

    ?ASSERT_SYNC_RECEIVED_FROM_LINE(21, Pid),
    ?ASSERT_SYNC_RECEIVED_FROM_LINE(22, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Check the events delivered
    % In particular we should register a bp hit event after the step onto line 21
    ?assertEqual(
        [
            {paused, {breakpoint, Pid, {test_step_over, go, 1}, {line, 20}}},
            {resumed, {continue, all}},
            {paused, {breakpoint, Pid, {test_step_over, go, 1}, {line, 21}}},
            {resumed, {continue, all}}
        ],
        edb_test_support:collected_events()
    ),

    ok.

test_multiprocess_parallel_steps(_Config) ->
    % Helper function that we'll use to check that processes are currently executing a step
    % Each step being awaiting on receiving a message, the Pid status can be either running or waiting
    AssertInStep = fun(Pid) ->
        {status, Status} = process_info(Pid, status),
        ?assert(Status =:= waiting orelse Status =:= running)
    end,

    % Add a breakpoint to start stepping from
    ok = edb:add_breakpoint(test_step_over, 100),

    % Spawn one process that will hit the breakpoint
    Pid1 = erlang:spawn(test_step_over, awaiting_steps, []),
    {ok, paused} = edb:wait(),

    % Sanity check that we hit the breakpoint
    ?assertEqual(
        #{Pid1 => #{line => 100, module => test_step_over}},
        edb:get_breakpoints_hit()
    ),

    % Engage the process into an awaiting step
    ok = edb:step_over(Pid1),

    % Spawn another process that will hit the breakpoint while the first is awaiting a step
    Pid2 = erlang:spawn(test_step_over, awaiting_steps, []),
    {ok, paused} = edb:wait(),

    % Pid2 should have hit its breakpoint
    ?assertEqual(
        #{Pid2 => #{line => 100, module => test_step_over}},
        edb:get_breakpoints_hit()
    ),

    % Pid1 in await, Pid2 on a step
    % Step Pid2 to resume the execution
    ok = edb:step_over(Pid2),

    % Now both processes should be awaiting
    AssertInStep(Pid1),
    AssertInStep(Pid2),

    % Unblock Pid1 and wait for it to complete its step
    Pid1 ! continue,
    edb:wait(),

    % Check that Pid1 has completed its step
    ?assertMatch(
        {ok, [
            #{mfa := {test_step_over, awaiting_steps, 0}, line := 101}
        ]},
        edb:stack_frames(Pid1)
    ),

    % Engage Pid1 on a step again to resume the execution
    ok = edb:step_over(Pid1),

    % Both processes await
    AssertInStep(Pid1),
    AssertInStep(Pid2),

    % Unblock Pid2 and wait for it to complete its (still first) step
    Pid2 ! continue,
    edb:wait(),

    % Pid2 should now have finally completed its step
    ?assertMatch(
        {ok, [
            #{mfa := {test_step_over, awaiting_steps, 0}, line := 101}
        ]},
        edb:stack_frames(Pid2)
    ),

    % Check the delivered events
    ?assertEqual(
        [
            {paused, {breakpoint, Pid1, {test_step_over, awaiting_steps, 0}, {line, 100}}},
            {resumed, {continue, all}},
            {paused, {breakpoint, Pid2, {test_step_over, awaiting_steps, 0}, {line, 100}}},
            {resumed, {continue, all}},
            {paused, {step, Pid1}},
            {resumed, {continue, all}},
            {paused, {step, Pid2}}
        ],
        edb_test_support:collected_events()
    ),

    ok.

%% ------------------------------------------------------------------
%% Test cases for test_step_out fixture
%% ------------------------------------------------------------------

test_step_out_of_external_closure(_Config) ->
    % Add a breakpoint to step from, in the external closure
    ok = edb:add_breakpoint(test_step_out, 71),

    % Spawn a process that will hit this breakpoint
    Pid = erlang:spawn(test_step_out, call_external_closure, [self()]),
    {ok, paused} = edb:wait(),

    ?ASSERT_SYNC_RECEIVED_FROM_LINE(62, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Sanity check that we hit the breakpoint
    ?assertEqual(
        #{Pid => #{line => 71, module => test_step_out}},
        edb:get_breakpoints_hit()
    ),

    % Check that we are inside the closure, called from call_external_closure
    % The closure-defining make_closure doesn't appear in the stack
    ?assertMatch(
        {ok, [
            #{mfa := {test_step_out, '-make_closure/1-fun-0-', 1}, line := 71},
            #{mfa := {test_step_out, call_external_closure, 1}, line := 64}
        ]},
        edb:stack_frames(Pid)
    ),

    % Step out the closure
    ok = edb:step_out(Pid),
    {ok, paused} = edb:wait(),

    ?assertMatch(
        {ok, [
            #{mfa := {test_step_out, call_external_closure, 1}, line := 65}
        ]},
        edb:stack_frames(Pid)
    ),

    ?ASSERT_SYNC_RECEIVED_FROM_LINE(71, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Sanity check that we can still step over in the caller
    ok = edb:step_over(Pid),
    {ok, paused} = edb:wait(),

    ?assertMatch(
        {ok, [
            #{mfa := {test_step_out, call_external_closure, 1}, line := 66}
        ]},
        edb:stack_frames(Pid)
    ),

    ?ASSERT_SYNC_RECEIVED_FROM_LINE(65, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Check the events delivered
    ?assertEqual(
        [
            {paused, {breakpoint, Pid, {test_step_out, '-make_closure/1-fun-0-', 1}, {line, 71}}},
            {resumed, {continue, all}},
            {paused, {step, Pid}},
            {resumed, {continue, all}},
            {paused, {step, Pid}}
        ],
        edb_test_support:collected_events()
    ),

    ok.

test_step_out_into_caller_handler(_Config) ->
    % Add a breakpoint to step from, just before raising an exception
    ok = edb:add_breakpoint(test_step_out, 95),

    % Spawn a process that will hit this breakpoint
    Pid = erlang:spawn(test_step_out, catch_exception, [self()]),
    {ok, paused} = edb:wait(),

    ?ASSERT_SYNC_RECEIVED_FROM_LINE(77, Pid),
    ?ASSERT_SYNC_RECEIVED_FROM_LINE(88, Pid),
    ?ASSERT_SYNC_RECEIVED_FROM_LINE(94, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Sanity check that we end on the expected program point
    ?assertMatch(
        {ok, [
            #{mfa := {test_step_out, raise_exception, 1}, line := 95},
            #{mfa := {test_step_out, indirect_raise_exception, 1}, line := 89},
            #{mfa := {test_step_out, catch_exception, 1}, line := 79}
        ]},
        edb:stack_frames(Pid)
    ),

    % Step out, that will raise the exception
    ok = edb:step_out(Pid),
    {ok, paused} = edb:wait(),

    % Check that we end up on the handler
    ?assertMatch(
        {ok, [
            #{mfa := {test_step_out, catch_exception, 1}, line := 82}
        ]},
        edb:stack_frames(Pid)
    ),

    % Sanity check that we can continue stepping
    ok = edb:step_over(Pid),
    ?ASSERT_SYNC_RECEIVED_FROM_LINE(82, Pid),
    ?ASSERT_NOTHING_ELSE_RECEIVED(),

    % Check the events delivered
    ?assertEqual(
        [
            {paused, {breakpoint, Pid, {test_step_out, raise_exception, 1}, {line, 95}}},
            {resumed, {continue, all}},
            {paused, {step, Pid}},
            {resumed, {continue, all}},
            {paused, {step, Pid}}
        ],
        edb_test_support:collected_events()
    ),

    ok.

%% ------------------------------------------------------------------
%% Test cases for test_code_inspection fixture
%% ------------------------------------------------------------------

test_fetch_fun_block_surrounding(_Config) ->
    %% Auxiliary function to check that a fun block is retrieved from all its lines
    CheckIsFunBlock = fun(FirstLine, LastLine) ->
        Lines = lists:seq(FirstLine, LastLine),
        [
            ?assertEqual(
                %% Add the line number to the block, to make it easier to debug
                {line, Line, {ok, Lines}},
                {line, Line, edb_server_code:fetch_fun_block_surrounding(test_code_inspection, Line)}
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

%% ------------------------------------------------------------------
%% Test cases for test_stackframes fixture
%% ------------------------------------------------------------------
test_shows_stackframes_of_process_in_breakpoint(Config) ->
    TestModuleSource = proplists:get_value(erl_source, Config),

    % stop in choose() base case
    ok = edb:add_breakpoint(test_stackframes, 5),

    Pid = erlang:spawn(test_stackframes, choose, [12, 8]),

    {ok, paused} = edb:wait(),

    {ok, Frames} = edb:stack_frames(Pid),
    ?assertEqual(
        [
            % choose(8, 8)
            #{id => 5, mfa => {test_stackframes, choose, 2}, source => TestModuleSource, line => 5},
            % choose(9, 8)
            #{id => 4, mfa => {test_stackframes, choose, 2}, source => TestModuleSource, line => 7},
            % choose(10, 8)
            #{id => 3, mfa => {test_stackframes, choose, 2}, source => TestModuleSource, line => 7},
            % choose(11, 8)
            #{id => 2, mfa => {test_stackframes, choose, 2}, source => TestModuleSource, line => 7},
            % choose(12, 8)
            #{id => 1, mfa => {test_stackframes, choose, 2}, source => TestModuleSource, line => 7}
        ],
        Frames
    ),

    % Can't select frames above the BP frame
    ?assertEqual(
        undefined,
        edb:stack_frame_vars(Pid, 7)
    ),

    % Can't select the BP frame
    ?assertEqual(
        undefined,
        edb:stack_frame_vars(Pid, 6)
    ),

    ?assertEqual(
        {ok, #{
            vars => #{
                <<"K">> => {value, 8},
                <<"N">> => {value, 8}
            },
            xregs => [
                {value, 8},
                {value, 8}
            ],
            yregs => []
        }},
        edb:stack_frame_vars(Pid, 5)
    ),
    ?assertEqual(
        {ok, #{
            % Y0 = var N
            yregs => [{value, 9}]
        }},
        edb:stack_frame_vars(Pid, 4)
    ),
    ?assertEqual(
        {ok, #{
            % Y0 = var N
            yregs => [{value, 10}]
        }},
        edb:stack_frame_vars(Pid, 3)
    ),
    ?assertEqual(
        {ok, #{
            % Y0 = var N
            yregs => [{value, 11}]
        }},
        edb:stack_frame_vars(Pid, 2)
    ),
    ?assertEqual(
        {ok, #{
            % Y0 = var N
            yregs => [{value, 12}]
        }},
        edb:stack_frame_vars(Pid, 1)
    ),
    ok.

test_shows_stackframes_of_paused_processes_not_in_breakpoint(Config) ->
    TestModuleSource = proplists:get_value(erl_source, Config),

    % stop replying in pong()
    ok = edb:add_breakpoint(test_stackframes, 26),

    PongPid = erlang:spawn_link(test_stackframes, pong, []),
    PingPid = erlang:spawn_link(test_stackframes, ping, [PongPid]),
    HangPid = erlang:spawn_link(test_stackframes, hang, [bim, 42, "foo"]),

    {ok, paused} = edb:wait(),

    % HangPid didn't hit a breakpoint, we can check its frames
    % We expect to see vars in X regs as it was suspended
    % while entering a call
    {ok, HangFrames} = edb:stack_frames(HangPid),
    ?assertEqual(
        [
            #{id => 1, mfa => {test_stackframes, hang, 3}, source => TestModuleSource, line => 30}
        ],
        HangFrames
    ),

    ?assertEqual(
        {ok, #{
            yregs => [],
            xregs => [
                % X0 = var X
                {value, bim},
                % X1 = var Y
                {value, 42},
                % X2 = var Z
                {value, "foo"}
            ]
        }},
        edb:stack_frame_vars(HangPid, 1)
    ),

    % PingPid didn't hit a breakpoint, we can check its frames
    % We expect to see vars in Y regs as it was suspended
    % while in a `receive`
    {ok, PingFrames} = edb:stack_frames(PingPid),
    ?assertEqual(
        [
            #{id => 2, mfa => {test_stackframes, ping, 2}, source => TestModuleSource, line => 16},
            #{id => 1, mfa => {test_stackframes, ping, 1}, source => TestModuleSource, line => 11}
        ],
        PingFrames
    ),

    ?assertEqual(
        undefined,
        edb:stack_frame_vars(PingPid, 3)
    ),
    ?assertEqual(
        {ok, #{
            yregs => [
                % Y0 = var Seq
                {value, 0},
                % Y1 = var Proc
                {value, PongPid}
            ],
            xregs => []
        }},
        edb:stack_frame_vars(PingPid, 2)
    ),
    ?assertEqual(
        {ok, #{
            yregs => []
        }},
        edb:stack_frame_vars(PingPid, 1)
    ),

    {ok, resumed} = edb:continue(),
    {ok, paused} = edb:wait(),
    ?assertEqual(
        {ok, #{
            yregs => [
                % Y0 = var Seq
                {value, 1},
                % Y1 = var Proc
                {value, PongPid}
            ],
            xregs => []
        }},
        edb:stack_frame_vars(PingPid, 2)
    ),

    {ok, resumed} = edb:continue(),
    {ok, paused} = edb:wait(),
    ?assertEqual(
        {ok, #{
            yregs => [
                % Y0 = var Seq
                {value, 2},
                % Y1 = var Proc
                {value, PongPid}
            ],
            xregs => []
        }},
        edb:stack_frame_vars(PingPid, 2)
    ),
    ok.

test_shows_stackframes_of_stepping_process(Config) ->
    TestModuleSource = proplists:get_value(erl_source, Config),

    % Stop before computing 42
    ok = edb:add_breakpoint(test_stackframes, 38),

    % Spawn a process that will hit this breakpoint
    Pid = erlang:spawn(test_stackframes, forty_two, []),
    {ok, paused} = edb:wait(),

    % Step to the next line
    ok = edb:step_over(Pid),
    {ok, paused} = edb:wait(),

    % Check that we can see the stack frames
    {ok, Frames} = edb:stack_frames(Pid),
    ?assertEqual(
        [
            % forty_two(1337)
            #{id => 2, mfa => {test_stackframes, forty_two, 1}, source => TestModuleSource, line => 39},
            % forty_two()
            #{id => 1, mfa => {test_stackframes, forty_two, 0}, source => TestModuleSource, line => 34}
        ],
        Frames
    ),

    % Can't select the step frame
    ?assertEqual(
        undefined,
        edb:stack_frame_vars(Pid, 3)
    ),

    % Can see variables in the top frame
    ?assertEqual(
        {ok, #{
            vars => #{
                <<"X">> => {value, 1337},
                <<"Six">> => {value, 6},
                <<"FortyTwo">> => {value, 42}
            },
            xregs => [
                {value, 1337}
            ],
            yregs => []
        }},
        edb:stack_frame_vars(Pid, 2)
    ),

    % Sanity check that we can select the bottom frame
    ?assertEqual(
        {ok, #{
            yregs => []
        }},
        edb:stack_frame_vars(Pid, 1)
    ),

    ok.

test_can_control_max_size_of_terms_in_vars_for_process_in_bp(_Config) ->
    % stop in hang() call
    ok = edb:add_breakpoint(test_stackframes, 31),

    LongList = lists:seq(1, 10_000),

    Pid = erlang:spawn_link(test_stackframes, hang, [
        "blah",
        <<"my binary">>,
        LongList
    ]),

    {ok, paused} = edb:wait(),

    % With size 0, we don't get any values
    ?assertEqual(
        {ok, #{
            yregs => [],
            xregs => [
                {too_large, 8, 0},
                {too_large, 4, 0},
                {too_large, 20_000, 0}
            ],
            vars => #{
                <<"X">> => {too_large, 8, 0},
                <<"Y">> => {too_large, 4, 0},
                <<"Z">> => {too_large, 20_000, 0}
            }
        }},
        edb:stack_frame_vars(Pid, 1, 0)
    ),

    % With size 3, we still don't get any values
    ?assertEqual(
        {ok, #{
            yregs => [],
            xregs => [
                {too_large, 8, 3},
                {too_large, 4, 3},
                {too_large, 20_000, 3}
            ],
            vars => #{
                <<"X">> => {too_large, 8, 3},
                <<"Y">> => {too_large, 4, 3},
                <<"Z">> => {too_large, 20_000, 3}
            }
        }},
        edb:stack_frame_vars(Pid, 1, 3)
    ),

    % With size 4, we get X1
    ?assertEqual(
        {ok, #{
            yregs => [],
            xregs => [
                {too_large, 8, 4},
                {value, <<"my binary">>},
                {too_large, 20_000, 4}
            ],
            vars => #{
                <<"X">> => {too_large, 8, 4},
                <<"Y">> => {value, <<"my binary">>},
                <<"Z">> => {too_large, 20_000, 4}
            }
        }},
        edb:stack_frame_vars(Pid, 1, 4)
    ),

    % With the default size, we can't show LongList
    ?assertEqual(
        {ok, #{
            yregs => [],
            xregs => [
                {value, "blah"},
                {value, <<"my binary">>},
                {too_large, 20_000, 2048}
            ],
            vars => #{
                <<"X">> => {value, "blah"},
                <<"Y">> => {value, <<"my binary">>},
                <<"Z">> => {too_large, 20_000, 2048}
            }
        }},
        edb:stack_frame_vars(Pid, 1)
    ),

    ok.

test_can_control_max_size_of_terms_in_vars_for_process_not_in_bp(_Config) ->
    % stop base-cae of choose(N, K)
    ok = edb:add_breakpoint(test_stackframes, 5),

    LongList = lists:seq(1, 10_000),
    PidNotInBp = erlang:spawn_link(test_stackframes, hang, ["blah", <<"my binary">>, LongList]),
    _PidInBp = erlang:spawn_link(test_stackframes, choose, [6, 3]),

    {ok, paused} = edb:wait(),

    % With size 0, we don't get any values
    ?assertEqual(
        {ok, #{
            yregs => [],
            xregs => [
                % X0 = var X
                {too_large, 8, 0},
                % X1 = var Y
                {too_large, 4, 0},
                % X2 = var Z
                {too_large, 20_000, 0}
            ]
        }},
        edb:stack_frame_vars(PidNotInBp, 1, 0)
    ),

    % With size 3, we still don't get any values
    ?assertEqual(
        {ok, #{
            yregs => [],
            xregs => [
                % X0 = var X
                {too_large, 8, 3},
                % X1 = var Y
                {too_large, 4, 3},
                % X2 = var Z
                {too_large, 20_000, 3}
            ]
        }},
        edb:stack_frame_vars(PidNotInBp, 1, 3)
    ),

    % With size 4, we get X1
    ?assertEqual(
        {ok, #{
            yregs => [],
            xregs => [
                % X0 = var X
                {too_large, 8, 4},
                % X1 = var Y
                {value, <<"my binary">>},
                % X2 = var Z
                {too_large, 20_000, 4}
            ]
        }},
        edb:stack_frame_vars(PidNotInBp, 1, 4)
    ),

    % With the default size, we can't show LongList
    ?assertEqual(
        {ok, #{
            yregs => [],
            xregs => [
                % X0 = var X
                {value, "blah"},
                % X1 = var Y
                {value, <<"my binary">>},
                % X2 = var Z
                {too_large, 20_000, 2048}
            ]
        }},
        edb:stack_frame_vars(PidNotInBp, 1)
    ),
    ok.

test_doesnt_show_stackframes_for_running_processes(_Config) ->
    ?assertEqual(
        not_paused,
        edb:stack_frames(self())
    ),
    ?assertEqual(
        not_paused,
        edb:stack_frame_vars(self(), 1)
    ),

    % Try again when other processes are paused
    edb:add_breakpoint(test_stackframes, 5),
    erlang:spawn(test_stackframes, choose, [8, 3]),
    {ok, paused} = edb:wait(),

    ?assertEqual(
        not_paused,
        edb:stack_frames(self())
    ),
    ?assertEqual(
        not_paused,
        edb:stack_frame_vars(self(), 1)
    ),
    ok.

test_shows_a_path_that_exists_for_otp_sources(_Config) ->
    InOtpCodePid = erlang:spawn_link(timer, sleep, [infinity]),

    % breakpoint in ping()
    ok = edb:add_breakpoint(test_stackframes, 11),
    _PingPid = erlang:spawn_link(test_stackframes, ping, [InOtpCodePid]),

    {ok, paused} = edb:wait(),

    {ok, Frames} = edb:stack_frames(InOtpCodePid),
    case Frames of
        [#{id := _, line := _, mfa := {timer, sleep, 1}, source := TimerSource}] when is_list(TimerSource) ->
            ?assert(filelib:is_file(TimerSource)),
            ok
    end.

%% ------------------------------------------------------------------
%% Test cases for test_format fixture
%% ------------------------------------------------------------------
test_format_works(_Config) ->
    ?assertEqual(
        <<"42">>,
        edb:format("~p", [42])
    ).

%% ------------------------------------------------------------------
%% Helpers
%% ------------------------------------------------------------------

compile_dummy_apps(Config) ->
    DataDir = proplists:get_value(data_dir, Config),
    PrivDir = proplists:get_value(priv_dir, Config),

    DataEbinDir = filename:join([DataDir, "dummy_apps", "ebin"]),
    DataSrcDir = filename:join([DataDir, "dummy_apps", "src"]),
    EbinDir = filename:join(PrivDir, "ebin"),
    ok = file:make_dir(EbinDir),

    CompileOpts = [{outdir, EbinDir}, debug_info, beam_debug_info],

    {ok, SrcFiles} = file:list_dir(DataSrcDir),
    [
        {ok, _} = compile:file(filename:join(DataSrcDir, SrcFile), CompileOpts)
     || SrcFile <- SrcFiles
    ],

    {ok, AppFiles} = file:list_dir(DataEbinDir),
    [
        {ok, _} = file:copy(filename:join(DataEbinDir, AppFile), filename:join(EbinDir, AppFile))
     || AppFile <- AppFiles
    ],

    code:add_patha(EbinDir),
    ok.

-spec spawn_idle_proc() -> pid().
spawn_idle_proc() ->
    Ctrl = self(),
    Pid = erlang:spawn(fun() ->
        Ctrl ! {sync, self()},
        wait_for_any_message()
    end),
    % Ensure the proc is in "Waiting" state before continuing
    receive
        {sync, Pid} -> ok
    end,
    Pid.

-spec wait_for_any_message() -> ok.
wait_for_any_message() ->
    receive
        _ -> ok
    end.
