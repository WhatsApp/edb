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

-module(edb_dap_language_SUITE).

-oncall("whatsapp_server_devx").

-include_lib("assert/include/assert.hrl").

%% CT callbacks
-export([
    all/0,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases
-export([
    test_set_breakpoints_with_custom_dap_language/1,
    test_set_breakpoints_when_source_maps_to_no_modules/1
]).

%% edb_dap_language callbacks
-export([init/0, source_to_modules/3]).

all() ->
    [
        test_set_breakpoints_with_custom_dap_language,
        test_set_breakpoints_when_source_maps_to_no_modules
    ].

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    edb_test_support:stop_all_peers(),
    ok.

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------
test_set_breakpoints_with_custom_dap_language(Config) ->
    {ok, Client, #{peer := Peer}} = start_session_with_custom_dap_language(Config),

    % Set breakpoints on synthetic source bar.erl
    Response = edb_dap_test_client:set_breakpoints(Client, #{
        source => #{path => ~"/tmp/bar.erl"},
        breakpoints => [#{line => Line} || Line <- [5, 6, 7, 14]]
    }),
    % Assert user-visible results. Line 5 is in both modules, 6 only in foo1,
    % 7 only in foo2, and 14 in neither.
    ?assertMatch(
        #{
            command := ~"setBreakpoints",
            type := response,
            success := true,
            body :=
                #{
                    breakpoints :=
                        [
                            #{line := 5, verified := true},
                            #{line := 6, verified := true},
                            #{line := 7, verified := true},
                            #{
                                line := 14,
                                message := ~"Line is not executable",
                                reason := ~"failed",
                                verified := false
                            }
                        ]
                }
        },
        Response
    ),

    % Run code on the debuggee and verify the accepted breakpoints are actually hit.
    #{success := true} = edb_dap_test_client:configuration_done(Client),

    % Line 5 is shared by foo1 and foo2. Line 6 only maps to foo1.
    {ok, ThreadId1, [#{name := ~"foo1:go/0", line := 5} | _]} =
        edb_dap_test_support:spawn_and_wait_for_bp(Client, Peer, {foo1, go, []}),

    #{success := true} = edb_dap_test_client:continue(Client, #{threadId => ThreadId1}),
    {ok, ThreadId2, [#{name := ~"foo1:go/0", line := 6} | _]} = edb_dap_test_support:wait_for_bp(Client),

    #{success := true} = edb_dap_test_client:continue(Client, #{threadId => ThreadId2}),

    % Line 5 is shared by foo1 and foo2. Line 7 only maps to foo2.
    {ok, ThreadId3, [#{name := ~"foo2:go/0", line := 5} | _]} =
        edb_dap_test_support:spawn_and_wait_for_bp(Client, Peer, {foo2, go, []}),

    #{success := true} = edb_dap_test_client:continue(Client, #{threadId => ThreadId3}),
    {ok, ThreadId4, [#{name := ~"foo2:go/0", line := 7} | _]} = edb_dap_test_support:wait_for_bp(Client),

    #{success := true} = edb_dap_test_client:continue(Client, #{threadId => ThreadId4}),
    ok.

test_set_breakpoints_when_source_maps_to_no_modules(Config) ->
    {ok, Client, #{}} = start_session_with_custom_dap_language(Config),

    Response = edb_dap_test_client:set_breakpoints(Client, #{
        source => #{path => ~"/tmp/unknown.erl"},
        breakpoints => [#{line => Line} || Line <- [3, 5]]
    }),
    ?assertMatch(
        #{
            command := ~"setBreakpoints",
            type := response,
            success := true,
            body :=
                #{
                    breakpoints :=
                        [
                            #{
                                line := 3,
                                message := ~"Module not found or failing to load",
                                reason := ~"failed",
                                verified := false
                            },
                            #{
                                line := 5,
                                message := ~"Module not found or failing to load",
                                reason := ~"failed",
                                verified := false
                            }
                        ]
                }
        },
        Response
    ),
    ok.

%%--------------------------------------------------------------------
%% Helpers
%%--------------------------------------------------------------------
-spec start_session_with_custom_dap_language(Config) -> {ok, Client, PeerInfo} when
    Config :: ct_suite:ct_config(),
    Client :: edb_dap_test_client:client(),
    PeerInfo :: edb_test_support:start_peer_result().
start_session_with_custom_dap_language(Config) ->
    DapServerBeamDir =
        case code:which(?MODULE) of
            ModuleBeam when ModuleBeam =/= non_existing -> filename:dirname(ModuleBeam)
        end,
    DapServerEnv = [
        {"ERL_AFLAGS",
            lists:flatten(
                io_lib:format("-pa ~s -eval application:set_env(edb,dap_language,~p)", [DapServerBeamDir, ?MODULE])
            )}
    ],
    edb_dap_test_support:start_session_via_launch(
        Config,
        #{},
        #{modules => custom_language_modules()},
        DapServerEnv
    ).

%%--------------------------------------------------------------------
%% edb_dap_language callbacks
%%--------------------------------------------------------------------
init() ->
    #{}.

% The test callback returns more than one runtime module for bar.erl.
source_to_modules(Path, _Lines, State) ->
    case filename:basename(Path, filename:extension(Path)) of
        ~"bar" -> {ok, [foo1, foo2], State};
        _ -> {ok, [], State}
    end.

custom_language_modules() ->
    [
        {source, [
            ~"-module(foo1).             %L01\n",
            ~"-export([go/0]).          %L02\n",
            ~"                          %L03\n",
            ~"go() ->                   %L04\n",
            ~"    both(),               %L05\n",
            ~"    only_foo1().          %L06\n",
            ~"                          %L07\n",
            ~"both() ->                 %L08\n",
            ~"    ok.                   %L09\n",
            ~"                          %L10\n",
            ~"only_foo1() ->            %L11\n",
            ~"    ok.                   %L12\n"
        ]},
        {source, [
            ~"-module(foo2).             %L01\n",
            ~"-export([go/0]).          %L02\n",
            ~"                          %L03\n",
            ~"go() ->                   %L04\n",
            ~"    both(),               %L05\n",
            ~"                          %L06\n",
            ~"    only_foo2().          %L07\n",
            ~"                          %L08\n",
            ~"both() ->                 %L09\n",
            ~"    ok.                   %L10\n",
            ~"                          %L11\n",
            ~"only_foo2() ->            %L12\n",
            ~"    ok.                   %L13\n"
        ]},
        {source, [
            ~"-module(foo3).             %L01\n",
            ~"-export([go/0]).          %L02\n",
            ~"                          %L03\n",
            ~"go() ->                   %L04\n",
            ~"    ok.                   %L05\n"
        ]}
    ].
