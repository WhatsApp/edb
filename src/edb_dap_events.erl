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
%%%-------------------------------------------------------------------
%% @doc DAP Events
%%      Handle events coming from the debugger.
%%      This function should be invoked by the DAP server.
%% @end
%%%-------------------------------------------------------------------
%%% % @format

-module(edb_dap_events).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-export([
    exited/3,
    stopped/2
]).

-include_lib("kernel/include/logger.hrl").

-type reaction() :: #{
    actions => [edb_dap_server:action()],
    state => edb_dap_state:t()
}.
-export_type([reaction/0]).

-spec exited(edb_dap_state:t(), Node :: node(), Reason :: term()) -> reaction().
exited(State, Node, Reason) ->
    case edb_dap_state:get_context(State) of
        #{target_node := #{name := Node}} ->
            ExitCode =
                case Reason of
                    connection_closed -> 0;
                    _ -> 1
                end,
            #{
                actions => [
                    {event, <<"exited">>, #{exitCode => ExitCode}},
                    {event, <<"terminated">>, #{}}
                ]
            };
        _ ->
            #{}
    end.

-spec stopped(edb_dap_state:t(), edb:stopped_event()) -> reaction().
stopped(_State, {breakpoint, Pid, _MFA, _Line}) ->
    StoppedEventBody = #{
        reason => ~"breakpoint",
        % On a BP, so we expect the source file of the top-frame
        % of this process to be shown
        preserveFocusHint => false,
        threadId => edb_dap_id_mappings:pid_to_thread_id(Pid),
        allThreadsStopped => true
    },
    #{actions => [{event, ~"stopped", StoppedEventBody}]};
stopped(_State, {step, Pid}) ->
    StoppedEventBody = #{
        reason => ~"step",
        % After a step action, so we expect the source file
        % of the top-frame of this process to be shown
        preserveFocusHint => false,
        threadId => edb_dap_id_mappings:pid_to_thread_id(Pid),
        allThreadsStopped => true
    },
    #{actions => [{event, <<"stopped">>, StoppedEventBody}]};
stopped(_State, Event) ->
    ?LOG_WARNING("Skipping stopped event: ~p", [Event]),
    #{}.
