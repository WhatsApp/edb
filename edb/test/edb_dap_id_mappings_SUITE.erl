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
-module(edb_dap_id_mappings_SUITE).

%% erlfmt:ignore
% @fb-only: 

%% Test server callbacks
-export([
    all/0
]).

%% Test cases
-export([
    test_it_works/1
]).

all() ->
    [test_it_works].

test_it_works(_Config) ->
    {ok, _} = edb_dap_id_mappings:start_link_thread_ids_server(),
    {ok, _} = edb_dap_id_mappings:start_link_frame_ids_server(),

    Pid1 = spawn(fun() -> ok end),
    Pid2 = spawn(fun() -> ok end),
    Pid3 = spawn(fun() -> ok end),
    Pid4 = spawn(fun() -> ok end),

    Frame1 = #{pid => Pid1, frame_no => 32},
    Frame2 = #{pid => Pid1, frame_no => 47},
    Frame3 = #{pid => Pid3, frame_no => 0},
    Frame4 = #{pid => Pid4, frame_no => 1},

    % Assigns a new id to each pid, only if needed
    ThreadId1 = 1 = edb_dap_id_mappings:pid_to_thread_id(Pid1),
    ThreadId2 = 2 = edb_dap_id_mappings:pid_to_thread_id(Pid2),
    ThreadId3 = 3 = edb_dap_id_mappings:pid_to_thread_id(Pid3),
    ThreadId4 = 4 = edb_dap_id_mappings:pid_to_thread_id(Pid4),

    ThreadId1 = edb_dap_id_mappings:pid_to_thread_id(Pid1),
    ThreadId2 = edb_dap_id_mappings:pid_to_thread_id(Pid2),
    ThreadId3 = edb_dap_id_mappings:pid_to_thread_id(Pid3),
    ThreadId4 = edb_dap_id_mappings:pid_to_thread_id(Pid4),

    % Looks up by ThreadId
    {ok, Pid1} = edb_dap_id_mappings:thread_id_to_pid(ThreadId1),
    {ok, Pid2} = edb_dap_id_mappings:thread_id_to_pid(ThreadId2),
    {ok, Pid3} = edb_dap_id_mappings:thread_id_to_pid(ThreadId3),
    {ok, Pid4} = edb_dap_id_mappings:thread_id_to_pid(ThreadId4),
    {error, not_found} = edb_dap_id_mappings:thread_id_to_pid(741),

    % Assigns a new id to each frame, only if needed
    FrameId1 = 1 = edb_dap_id_mappings:pid_frame_to_frame_id(Frame1),
    FrameId2 = 2 = edb_dap_id_mappings:pid_frame_to_frame_id(Frame2),
    FrameId3 = 3 = edb_dap_id_mappings:pid_frame_to_frame_id(Frame3),
    FrameId4 = 4 = edb_dap_id_mappings:pid_frame_to_frame_id(Frame4),

    FrameId1 = edb_dap_id_mappings:pid_frame_to_frame_id(Frame1),
    FrameId2 = edb_dap_id_mappings:pid_frame_to_frame_id(Frame2),
    FrameId3 = edb_dap_id_mappings:pid_frame_to_frame_id(Frame3),
    FrameId4 = edb_dap_id_mappings:pid_frame_to_frame_id(Frame4),

    % Looks up by FrameId
    {ok, Frame1} = edb_dap_id_mappings:frame_id_to_pid_frame(FrameId1),
    {ok, Frame2} = edb_dap_id_mappings:frame_id_to_pid_frame(FrameId2),
    {ok, Frame3} = edb_dap_id_mappings:frame_id_to_pid_frame(FrameId3),
    {ok, Frame4} = edb_dap_id_mappings:frame_id_to_pid_frame(FrameId4),
    {error, not_found} = edb_dap_id_mappings:frame_id_to_pid_frame(741),

    % Can reset ids, but ThreadIds remain
    edb_dap_id_mappings:reset(),
    {ok, Pid1} = edb_dap_id_mappings:thread_id_to_pid(ThreadId1),
    {error, not_found} = edb_dap_id_mappings:frame_id_to_pid_frame(FrameId1),
    FrameId1 = 1 = edb_dap_id_mappings:pid_frame_to_frame_id(Frame1),
    {ok, Frame1} = edb_dap_id_mappings:frame_id_to_pid_frame(FrameId1),

    ok = gen_server:stop(edb_dap_thread_id_mappings),
    ok = gen_server:stop(edb_dap_frame_id_mappings).
