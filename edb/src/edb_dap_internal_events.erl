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
%% @doc Handle events coming from the debugger.
%% @end
%%%-------------------------------------------------------------------
%%% % @format

-module(edb_dap_internal_events).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-export([handle/2]).

-include_lib("kernel/include/logger.hrl").

%%%---------------------------------------------------------------------------------
%%% Types
%%%---------------------------------------------------------------------------------

-type reaction() :: #{
    actions => [{event, edb_dap_event:event()}],
    state => edb_dap_server:state()
}.
-export_type([reaction/0]).

%%%---------------------------------------------------------------------------------
%%% Public API
%%%---------------------------------------------------------------------------------
-spec handle(EdbEvent, State) -> Reaction when
    EdbEvent :: edb:event(),
    State :: edb_dap_server:state(),
    Reaction :: edb_dap_internal_events:reaction().
handle({paused, PausedEvent}, State) ->
    paused_impl(State, PausedEvent);
handle({nodedown, Node, Reason}, State) ->
    nodedown_impl(State, Node, Reason);
handle(Event, _State) ->
    ?LOG_DEBUG("Skipping event: ~p", [Event]),
    #{}.

%%%---------------------------------------------------------------------------------
%%% Implementations
%%%---------------------------------------------------------------------------------
-spec nodedown_impl(edb_dap_server:state(), Node :: node(), Reason :: term()) -> reaction().
nodedown_impl(State, Node, Reason) ->
    case State of
        #{context := #{target_node := #{name := Node}}} ->
            ExitCode =
                case Reason of
                    connection_closed -> 0;
                    _ -> 1
                end,
            #{
                state => #{state => terminating},
                actions => [
                    {event, edb_dap_event:exited(ExitCode)},
                    {event, edb_dap_event:terminated()}
                ]
            };
        #{context := _} ->
            #{}
    end.

-spec paused_impl(edb_dap_server:state(), edb:paused_event()) -> reaction().
paused_impl(_State, {breakpoint, Pid, _MFA, _Line}) ->
    StoppedEvent = edb_dap_event:stopped(#{
        reason => ~"breakpoint",
        % On a BP, so we expect the source file of the top-frame
        % of this process to be shown
        preserveFocusHint => false,
        threadId => edb_dap_id_mappings:pid_to_thread_id(Pid),
        allThreadsStopped => true
    }),
    #{actions => [{event, StoppedEvent}]};
paused_impl(_State, {step, Pid}) ->
    StoppedEvent = edb_dap_event:stopped(#{
        reason => ~"step",
        % After a step action, so we expect the source file
        % of the top-frame of this process to be shown
        preserveFocusHint => false,
        threadId => edb_dap_id_mappings:pid_to_thread_id(Pid),
        allThreadsStopped => true
    }),
    #{actions => [{event, StoppedEvent}]};
paused_impl(_State, pause) ->
    StoppedEvent = edb_dap_event:stopped(#{
        reason => ~"pause",
        preserveFocusHint => true,
        allThreadsStopped => true
    }),
    #{actions => [{event, StoppedEvent}]};
paused_impl(_State, Event) ->
    ?LOG_WARNING("Skipping paused event: ~p", [Event]),
    #{}.
