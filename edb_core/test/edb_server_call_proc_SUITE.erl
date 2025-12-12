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

-module(edb_server_call_proc_SUITE).

%% erlfmt:ignore
% @fb-only
-typing([eqwalizer]).

-include_lib("assert/include/assert.hrl").

%% Test server callbacks
-export([
    all/0,
    groups/0,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases
-export([
    test_safe_send_recv_success/1,
    test_safe_send_recv_noproc/1,
    test_safe_send_recv_suspended/1,
    test_safe_send_recv_timeout/1,
    test_code_where_is_file_works/1
]).

all() ->
    [
        {group, generic_api},
        {group, supported_calls}
    ].

groups() ->
    [
        {generic_api, [
            test_safe_send_recv_success,
            test_safe_send_recv_noproc,
            test_safe_send_recv_suspended,
            test_safe_send_recv_timeout
        ]},

        {supported_calls, [
            test_code_where_is_file_works
        ]}
    ].

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok = ping_server_stop(),
    ok.

%%--------------------------------------------------------------------
%% TEST CASES

test_safe_send_recv_success(_Config) ->
    ok = ping_server_start_link(),

    Ref = erlang:make_ref(),
    ?assertEqual(
        {call_ok, {pong, Ref}},
        ping_server_safe_call({ping, Ref})
    ),
    ok.

test_safe_send_recv_noproc(_Config) ->
    % ping_server is not started
    Ref = erlang:make_ref(),
    ?assertEqual(
        {call_error, noproc},
        ping_server_safe_call({ping, Ref})
    ),
    ok.

test_safe_send_recv_suspended(_Config) ->
    ok = ping_server_start_link(),

    case erlang:whereis(ping_server) of
        Pid when is_pid(Pid) ->
            erlang:suspend_process(Pid)
    end,

    Ref = erlang:make_ref(),
    ?assertEqual(
        {call_error, suspended},
        ping_server_safe_call({ping, Ref})
    ),
    ok.

test_safe_send_recv_timeout(_Config) ->
    ok = ping_server_start_link(),

    ?assertEqual(
        {call_error, timeout},
        ping_server_safe_call(an_invalid_request)
    ),
    ok.

test_code_where_is_file_works(_Config) ->
    MyBeam = atom_to_list(?MODULE) ++ ".beam",
    ?assertMatch(
        {call_ok, MyBeamPath} when is_list(MyBeamPath),
        edb_server_call_proc:code_where_is_file(MyBeam)
    ),

    MyBean = atom_to_list(?MODULE) ++ ".bean",
    ?assertMatch(
        {call_ok, non_existing},
        edb_server_call_proc:code_where_is_file(MyBean)
    ).

%%--------------------------------------------------------------------
%% HELPERS

-spec ping_server_safe_call(Req :: term()) -> edb_server_call_proc:result(dynamic()).
ping_server_safe_call(Req) ->
    Ref = erlang:make_ref(),
    edb_server_call_proc:safe_send_recv(
        ping_server,
        fun() -> {self(), Ref, Req} end,
        fun() ->
            receive
                {Ref, Resp} -> Resp
            end
        end,
        1_000
    ).

-spec ping_server_start_link() -> ok.
ping_server_start_link() ->
    Pid = erlang:spawn(
        fun Loop() ->
            receive
                {From, Ref, {ping, X}} ->
                    From ! {Ref, {pong, X}},
                    Loop()
            end
        end
    ),
    true = erlang:register(ping_server, Pid),
    ok.

-spec ping_server_stop() -> ok.
ping_server_stop() ->
    MonitorRef = erlang:monitor(process, ping_server),
    case erlang:whereis(ping_server) of
        undefined ->
            ok;
        Pid when is_pid(Pid) ->
            erlang:exit(Pid, kill),
            receive
                {'DOWN', MonitorRef, process, _, _} ->
                    ok
            after 1_000 ->
                error(timeout_stopping_ping_server)
            end
    end.
