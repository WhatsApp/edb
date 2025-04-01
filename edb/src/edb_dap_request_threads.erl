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

%%% % @format

-module(edb_dap_request_threads).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-behaviour(edb_dap_request).

-export([parse_arguments/1, handle/2]).

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------

%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_Threads
-type arguments() :: #{}.

-type threads() :: #{
    threads := [thread()]
}.
-type thread() :: #{
    id := number(),
    name := binary()
}.
-export_type([arguments/0, threads/0]).
-export_type([thread/0]).

%% ------------------------------------------------------------------
%% Behaviour implementation
%% ------------------------------------------------------------------
-spec parse_arguments(edb_dap:arguments()) -> {ok, arguments()} | {error, Reason} when Reason :: binary().
parse_arguments(Args) ->
    edb_dap_request:parse_empty_arguments(Args).

-spec handle(State, Args) -> edb_dap_request:reaction(threads()) when
    State :: edb_dap_server:state(),
    Args :: arguments().
handle(#{state := attached}, _Args) ->
    ProcessesInfo = edb:processes([registered_name, message_queue_len]),
    Threads = maps:fold(fun thread/3, [], ProcessesInfo),
    #{response => edb_dap_request:success(#{threads => Threads})};
handle(_UnexpectedState, _) ->
    edb_dap_request:unexpected_request().

%% ------------------------------------------------------------------
%% Helpers
%% ------------------------------------------------------------------
-spec thread(pid(), edb:process_info(), [thread()]) -> [thread()].
thread(Pid, Info, Acc) ->
    Id = edb_dap_id_mappings:pid_to_thread_id(Pid),
    [
        #{
            id => Id,
            name => thread_name(Pid, Info)
        }
        | Acc
    ].

-spec thread_name(pid(), edb:process_info()) -> binary().
thread_name(Pid, Info) ->
    ProcessNameLabel = process_name_label(Pid, Info),
    MessageQueueLenLabel = message_queue_len_label(Info),
    edb:format(~"~s~s", [ProcessNameLabel, MessageQueueLenLabel]).

-spec process_name_label(pid(), edb:process_info()) -> binary().
process_name_label(Pid, Info) ->
    case maps:get(registered_name, Info, undefined) of
        undefined ->
            edb:format(~"~p", [Pid]);
        RegisteredName ->
            edb:format(~"~p (~p)", [Pid, RegisteredName])
    end.

-spec message_queue_len_label(edb:process_info()) -> binary().
message_queue_len_label(Info) ->
    case maps:get(message_queue_len, Info, 0) of
        0 ->
            ~"";
        N ->
            edb:format(~" (messages: ~p)", [N])
    end.
