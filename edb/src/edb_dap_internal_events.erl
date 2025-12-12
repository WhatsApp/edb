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
%%% % @format

-module(edb_dap_internal_events).

%% erlfmt:ignore
% @fb-only
-moduledoc """
Handle events coming from the debugger.
""".
-compile(warn_missing_spec_all).

-export([handle_edb_event/2]).

-include_lib("kernel/include/logger.hrl").
-include_lib("edb/include/edb_dap.hrl").

%%%---------------------------------------------------------------------------------
%%% Types
%%%---------------------------------------------------------------------------------

-type reaction() :: #{
    actions => [{event, edb_dap_event:event()}],
    new_state => edb_dap_server:state(),
    error => edb_dap_server:error()
}.
-export_type([reaction/0]).

%%%---------------------------------------------------------------------------------
%%% Public API
%%%---------------------------------------------------------------------------------

-spec handle_edb_event(EdbEvent, State) -> Reaction when
    EdbEvent :: edb:event(),
    State :: edb_dap_server:state(),
    Reaction :: reaction().
handle_edb_event({reverse_attach, Ref, Result}, #{reverse_attach_ref := Ref} = State) ->
    reverse_attach_impl(Result, State);
handle_edb_event({reverse_attach_timeout, _Ref}, State) ->
    reverse_attach_timeout_impl(State);
handle_edb_event({paused, PausedEvent}, State) ->
    paused_impl(State, PausedEvent);
handle_edb_event({nodedown, Node, Reason}, State) ->
    nodedown_impl(State, Node, Reason);
handle_edb_event(Event, _State) ->
    ?LOG_DEBUG("Skipping event: ~p", [Event]),
    #{}.

%%%---------------------------------------------------------------------------------
%%% Implementations
%%%---------------------------------------------------------------------------------
-spec nodedown_impl(edb_dap_server:state(), Node :: node(), Reason :: term()) -> reaction().
nodedown_impl(#{node := Node}, Node, Reason) ->
    ExitCode =
        case Reason of
            connection_closed -> 0;
            _ -> 1
        end,
    #{
        new_state => #{state => terminating},
        actions => [
            {event, edb_dap_event:exited(ExitCode)},
            {event, edb_dap_event:terminated()}
        ]
    };
nodedown_impl(State, Node, _Reason) ->
    ?LOG_WARNING("Unexpected nodedown event for node ~p received while in state ~p", [Node, State]),
    #{}.

-spec paused_impl(edb_dap_server:state(), edb:paused_event()) -> reaction().
paused_impl(#{state := launching}, pause) ->
    % Reverse-attaching in progress, the node has been paused
    #{};
paused_impl(#{state := attached}, {breakpoint, Pid, _MFA, _Line}) ->
    StoppedEvent = edb_dap_event:stopped(#{
        reason => ~"breakpoint",
        % On a BP, so we expect the source file of the top-frame
        % of this process to be shown
        preserveFocusHint => false,
        threadId => edb_dap_id_mappings:pid_to_thread_id(Pid),
        allThreadsStopped => true
    }),
    #{actions => [{event, StoppedEvent}]};
paused_impl(#{state := attached}, {function_breakpoint, Pid, _MFA, _Line}) ->
    StoppedEvent = edb_dap_event:stopped(#{
        reason => ~"function_breakpoint",
        % On a BP, so we expect the source file of the top-frame
        % of this process to be shown
        preserveFocusHint => false,
        threadId => edb_dap_id_mappings:pid_to_thread_id(Pid),
        allThreadsStopped => true
    }),
    #{actions => [{event, StoppedEvent}]};
paused_impl(#{state := attached}, {step, Pid}) ->
    StoppedEvent = edb_dap_event:stopped(#{
        reason => ~"step",
        % After a step action, so we expect the source file
        % of the top-frame of this process to be shown
        preserveFocusHint => false,
        threadId => edb_dap_id_mappings:pid_to_thread_id(Pid),
        allThreadsStopped => true
    }),
    #{actions => [{event, StoppedEvent}]};
paused_impl(#{state := attached}, pause) ->
    StoppedEvent = edb_dap_event:stopped(#{
        reason => ~"pause",
        preserveFocusHint => true,
        allThreadsStopped => true
    }),
    #{actions => [{event, StoppedEvent}]};
paused_impl(#{state := S}, Event) ->
    ?LOG_WARNING("Skipping paused event: ~p when ~p", [Event, S]),
    #{}.

-spec reverse_attach_impl(Result, State) -> Reaction when
    Result :: edb:reverse_attachment_event(),
    State :: edb_dap_server:state(),
    Reaction :: reaction().
reverse_attach_impl({attached, Node}, State0 = #{state := launching}) ->
    State1 = maps:without([shell_process_id], State0),

    % elp:ignore W0014 -- debugger relies on dist
    ProcessId = list_to_integer(erpc:call(Node, os, getpid, [])),

    AttachType0 = maps:with([shell_process_id], State0),
    AttachType1 = AttachType0#{request => launch, process_id => ProcessId},
    #{
        actions => [{event, edb_dap_event:initialized()}],
        new_state => State1#{
            state => configuring,
            type => AttachType1,
            node => Node
        }
    };
reverse_attach_impl({error, Node, {bootstrap_failed, BootstrapFailure}}, #{state := launching}) ->
    #{
        new_state => #{state => terminating},
        actions => [{event, edb_dap_event:terminated()}],
        error =>
            {user_error, ?ERROR_NOT_SUPPORTED,
                io_lib:format("EDB bootstrap failed on node ~p: ~p", [Node, BootstrapFailure])}
    };
reverse_attach_impl(Event, #{state := S}) ->
    ?LOG_WARNING("Unexpected reverse_attach event: ~p when ~p", [Event, S]),
    #{}.

-spec reverse_attach_timeout_impl(edb_dap_server:state()) -> reaction().
reverse_attach_timeout_impl(#{state := launching}) ->
    #{
        new_state => #{state => terminating},
        actions => [{event, edb_dap_event:terminated()}],
        error => {user_error, ?ERROR_TIMED_OUT, ~"Timed out waiting for node to be up"}
    };
reverse_attach_timeout_impl(#{state := S}) ->
    ?LOG_WARNING("Unexpected reverse_attach_timeout event when ~p", [S]),
    #{}.
