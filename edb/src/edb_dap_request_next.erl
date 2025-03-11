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

-module(edb_dap_request_next).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-behaviour(edb_dap_request).

-export([parse_arguments/1, handle/2]).

-export([stepper/3]).

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------

%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_Next
-type arguments() :: #{
    %  Specifies the thread for which to resume execution for one step (of the
    %  given granularity).
    threadId := number(),

    %  If this flag is true, all other suspended threads are not resumed.
    singleThread => boolean(),

    %  Stepping granularity. If no granularity is specified, a granularity of
    %  `statement` is assumed.
    granularity => edb_dap:stepping_granularity()
}.

-export_type([arguments/0]).

%% ------------------------------------------------------------------
%% Behaviour implementation
%% ------------------------------------------------------------------
-spec parse_arguments(edb_dap:arguments()) -> {ok, arguments()}.
parse_arguments(Args) ->
    {ok, Args}.

-spec handle(State, Args) -> edb_dap_request:reaction() when
    State :: edb_dap_server:state(),
    Args :: arguments().
handle(State, #{threadId := ThreadId}) ->
    stepper(State, ThreadId, 'step-over').

%% ------------------------------------------------------------------
%% Generic stepping implementation
%% ------------------------------------------------------------------
-spec stepper(State, ThreadId, StepType) -> edb_dap_request:reaction() when
    State :: edb_dap_server:state(),
    ThreadId :: edb_dap:thread_id(),
    StepType :: 'step-over' | 'step-out'.
stepper(#{state := attached}, ThreadId, StepType) ->
    Pid = edb_dap_request:thread_id_to_pid(ThreadId),
    StepFun =
        case StepType of
            'step-over' -> fun edb:step_over/1;
            'step-out' -> fun edb:step_out/1
        end,
    case StepFun(Pid) of
        ok ->
            edb_dap_id_mappings:reset(),
            #{response => edb_dap_request:success()};
        {error, not_paused} ->
            edb_dap_request:not_paused(Pid);
        {error, no_abstract_code} ->
            edb_dap_request:unsupported(~"Module not compiled with debug_info");
        {error, {cannot_breakpoint, ModuleName}} ->
            edb_dap_request:unsupported(
                io_lib:format("Module ~s not compiled with beam_debug_info", [ModuleName])
            );
        {error, {beam_analysis, Err}} ->
            throw({beam_analysis, Err})
    end;
stepper(_UnexpectedState, _, _) ->
    edb_dap_request:unexpected_request().
