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
-module(edb_main_SUITE).

%% erlfmt:ignore
% @fb-only

% @fb-only
-include_lib("stdlib/include/assert.hrl").
-include_lib("common_test/include/ct.hrl").
-include_lib("kernel/include/file.hrl").

%% Test server callbacks
-export([
    all/0,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases
-export([
    escript_executable/1,
    escript_dap/1
]).

-define(EDB, "edb").

all() ->
    [
        escript_executable,
        escript_dap
    ].

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok = edb_test_support:stop_all_peer_nodes(),
    ok.

escript_executable(Config) ->
    DataDir = ?config(data_dir, Config),
    Escript = filename:join([DataDir, ?EDB]),
    ?assert(filelib:is_file(Escript), "Escript should exists"),
    {ok, FileInfo} = file:read_file_info(Escript),
    ?assertEqual(8#111, FileInfo#file_info.mode band 8#111, "Escript should be executable").

escript_dap(Config) ->
    {ok, Peer, Node, Cookie} = edb_test_support:start_peer_node(Config, "debuggee"),
    {ok, Client, Cwd} = edb_dap_test_support:start_session(Config, Node, Cookie),

    Response3 = edb_dap_test_client:threads(Client, #{}),
    ?assertMatch(#{request_seq := 3, type := response, success := true}, Response3),

    Line = 32,
    {ok, Module, SourcePath} = edb_dap_test_support:load_file_and_set_breakpoints(
        Config,
        Peer,
        Client,
        {filename, "factorial.erl"},
        [Line]
    ),

    spawn(fun() -> 120 = peer:call(Peer, Module, fact, [5]) end),
    {ok, [StoppedEvent]} = edb_dap_test_client:wait_for_event(<<"stopped">>, Client),
    ?assertMatch(
        #{
            event := <<"stopped">>,
            body := #{reason := <<"breakpoint">>, preserveFocusHint := false, threadId := _, allThreadsStopped := true}
        },
        StoppedEvent
    ),

    ThreadId = maps:get(threadId, maps:get(body, StoppedEvent)),
    Response5 = edb_dap_test_client:stack_trace(Client, #{threadId => ThreadId}),
    ?assertMatch(
        #{
            request_seq := 5,
            type := response,
            success := true,
            body := #{stackFrames := _}
        },
        Response5
    ),
    StackFrames = maps:get(stackFrames, maps:get(body, Response5)),

    FactorialPath = <<Cwd/binary, "factorial.erl">>,
    ?assertMatch(
        [
            #{
                id := 1,
                line := 32,
                name := <<"factorial:fact/1">>,
                column := 0,
                source := #{name := <<"factorial">>, path := FactorialPath}
            },
            #{
                id := 2,
                line := 1548,
                name := <<"peer:'-do_call/4-fun-0-'/5">>,
                column := 0,
                source := #{name := <<"peer">>, path := _}
            }
        ],
        StackFrames
    ),

    FrameId = 1,
    Response6 = edb_dap_test_client:scopes(Client, #{frameId => FrameId}),
    ?assertMatch(
        #{
            command := <<"scopes">>,
            type := response,
            success := true,
            body := #{
                scopes := [
                    #{
                        name := <<"Locals">>,
                        expensive := false,
                        presentationHint := <<"locals">>,
                        variablesReference := 1
                    }
                ]
            },
            request_seq := 6
        },
        Response6
    ),

    #{body := #{scopes := Scopes}} = Response6,
    [VariablesReferenceLocals] = lists:filtermap(
        fun
            (#{name := <<"Locals">>, variablesReference := VR}) -> {true, VR};
            (_) -> false
        end,
        Scopes
    ),
    Response7 = edb_dap_test_client:variables(Client, #{variablesReference => VariablesReferenceLocals}),
    ?assertMatch(
        #{
            command := <<"variables">>,
            type := response,
            success := true,
            body := #{
                variables := _
            },
            request_seq := 7
        },
        Response7
    ),

    ok = edb_dap_test_support:set_breakpoints(Client, SourcePath, []),

    Response8 = edb_dap_test_client:continue(Client, #{}),
    ?assertMatch(
        #{
            request_seq := 9,
            type := response,
            success := true,
            body := #{allThreadsContinued := true}
        },
        Response8
    ),

    Response9 = edb_dap_test_client:disconnect(Client, #{}),
    ?assertMatch(
        #{
            command := <<"disconnect">>,
            type := response,
            request_seq := 10,
            success := true
        },
        Response9
    ).