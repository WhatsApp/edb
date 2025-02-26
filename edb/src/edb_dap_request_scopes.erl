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

-module(edb_dap_request_scopes).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-behaviour(edb_dap_request).

-export([parse_arguments/1, handle/2]).

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------

%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_Scopes
-type arguments() :: #{
    % Retrieve the scopes for the stack frame identified by `frameId`. The
    % `frameId` must have been obtained in the current suspended state.
    frameId := number()
}.

-type response_body() ::
    #{
        % The scopes of the stack frame. If the array has length zero, there are no
        % scopes available.
        scopes := [scope()]
    }.

-type scope() :: #{
    % Name of the scope such as 'Arguments', 'Locals', or 'Registers'. This
    % string is shown in the UI as is and can be translated.
    name := binary(),
    % A hint for how to present this scope in the UI. If this attribute is
    % missing, the scope is shown with a generic UI.
    % Values:
    %   'arguments': Scope contains method arguments.
    %   'locals': Scope contains local variables.
    %   'registers': Scope contains registers. Only a single `registers` scope
    %                should be returned from a `scopes` request.
    %   'returnValue': Scope contains one or more return values.
    presentationHint => binary(),
    % The variables of this scope can be retrieved by passing the value of
    % `variablesReference` to the `variables` request as long as execution
    % remains suspended.
    variablesReference := number(),
    % The number of named variables in this scope.
    % The client can use this information to present the variables in a paged UI
    % and fetch them in chunks.
    namedVariables => number(),
    % The number of indexed variables in this scope.
    % The client can use this information to present the variables in a paged UI
    % and fetch them in chunks.
    indexedVariables => number(),
    % If true, the number of variables in this scope is large or expensive to
    % retrieve.
    expensive := boolean(),
    % The source for this scope.
    source => edb_dap:source(),
    % The start line of the range covered by this scope.
    line => number(),
    % Start position of the range covered by the scope.
    % It is measured in UTF-16
    % code units and the client capability `columnsStartAt1` determines whether
    % it is 0- or 1-based.
    column => number(),
    % The end line of the range covered by this scope.
    endLine => number(),
    % End position of the range covered by the scope.
    % It is measured in UTF-16
    % code units and the client capability `columnsStartAt1` determines whether
    % it is 0- or 1-based.
    endColumn => number()
}.

-export_type([arguments/0, response_body/0, scope/0]).

%% ------------------------------------------------------------------
%% Behaviour implementation
%% ------------------------------------------------------------------
-spec parse_arguments(edb_dap:arguments()) -> {ok, arguments()}.
parse_arguments(Args) ->
    {ok, Args}.

-spec handle(State, Args) -> edb_dap_request:reaction(response_body()) when
    State :: edb_dap_state:t(),
    Args :: arguments().
handle(State, #{frameId := FrameId}) ->
    {ok, #{pid := Pid, frame_no := FrameNo}} = edb_dap_id_mappings:frame_id_to_pid_frame(FrameId),
    VariablesScopes =
        case edb:stack_frame_vars(Pid, FrameNo, _MaxTermSize = 1) of
            {ok, #{vars := _}} ->
                [
                    #{
                        name => <<"Locals">>,
                        presentationHint => <<"locals">>,
                        variablesReference => edb_dap_id_mappings:frame_scope_to_var_reference(#{
                            frame => FrameId, scope => locals
                        }),
                        expensive => false
                    }
                ];
            {ok, Frames} when is_map(Frames) ->
                [
                    #{
                        name => <<"Registers">>,
                        presentationHint => <<"registers">>,
                        variablesReference => edb_dap_id_mappings:frame_scope_to_var_reference(#{
                            frame => FrameId, scope => registers
                        }),
                        expensive => false
                    }
                ];
            _ ->
                []
        end,
    #{target_node := #{name := Node}} = edb_dap_state:get_context(State),
    MessagesScopes =
        % elp:ignore W0014 (cross_node_eval)
        case erpc:call(Node, erlang, process_info, [Pid, message_queue_len]) of
            {message_queue_len, N} when N > 0 ->
                [
                    #{
                        name => <<"Messages">>,
                        variablesReference => edb_dap_id_mappings:frame_scope_to_var_reference(#{
                            frame => FrameId, scope => messages
                        }),
                        expensive => false
                    }
                ];
            _ ->
                []
        end,
    #{
        response => #{
            success => true,
            body => #{
                scopes => MessagesScopes ++ VariablesScopes
            }
        }
    }.
