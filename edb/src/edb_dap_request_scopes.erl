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
    presentationHint =>
        'arguments' | 'locals' | 'registers' | 'returnValue',
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

-spec arguments_template() -> edb_dap_parse:template().
arguments_template() ->
    #{
        frameId => edb_dap_parse:number()
    }.

%% ------------------------------------------------------------------
%% Behaviour implementation
%% ------------------------------------------------------------------
-spec parse_arguments(edb_dap:arguments()) -> {ok, arguments()} | {error, Reason :: binary()}.
parse_arguments(Args) ->
    Template = arguments_template(),
    edb_dap_parse:parse(Template, Args, reject_unknown).

-spec handle(State, Args) -> edb_dap_request:reaction(response_body()) when
    State :: edb_dap_server:state(),
    Args :: arguments().
handle(#{state := attached, client_info := ClientInfo}, #{frameId := FrameId}) ->
    {ok, #{pid := Pid, frame_no := FrameNo}} = edb_dap_id_mappings:frame_id_to_pid_frame(FrameId),
    EvalResult = edb_dap_eval_delegate:eval(#{
        context => {Pid, FrameNo},
        function => edb_dap_eval_delegate:scopes_callback(Pid)
    }),
    Scopes =
        case EvalResult of
            not_paused ->
                edb_dap_request:not_paused(Pid);
            undefined ->
                throw({failed_to_resolve_scope, #{pid => Pid, frame_no => FrameNo}});
            {ok, RawScopes} ->
                [make_scope(ClientInfo, FrameId, RawScope) || RawScope <- RawScopes];
            {eval_error, Error} ->
                throw({failed_to_eval_scopes, Error})
        end,
    #{
        response => edb_dap_request:success(#{
            scopes => Scopes
        })
    };
handle(_UnexpectedState, _) ->
    edb_dap_request:unexpected_request().

% --------------------------------------------------------------------
% Helpers
% --------------------------------------------------------------------
-spec make_scope(ClientInfo, FrameId, RawScope) -> scope() when
    ClientInfo :: edb_dap_server:client_info(),
    FrameId :: edb_dap_id_mappings:id(),
    RawScope :: edb_dap_eval_delegate:scope().
make_scope(ClientInfo, FrameId, RawScope = #{type := Type, variables := RawVars}) ->
    Scope0 =
        case Type of
            process ->
                #{
                    name => ~"Process"
                };
            locals ->
                #{
                    name => ~"Locals",
                    presentationHint => locals
                };
            registers ->
                #{
                    name => ~"Registers",
                    presentationHint => registers
                }
        end,
    VariablesRef = edb_dap_request_variables:scope_variables_ref(ClientInfo, FrameId, RawScope),
    Scope1 = Scope0#{
        variablesReference => VariablesRef,
        expensive => false
    },
    Scope2 =
        case ClientInfo of
            #{supportsVariablePaging := true} when VariablesRef > 0 ->
                Scope1#{
                    indexedVariables => length(RawVars)
                };
            _ ->
                Scope1
        end,
    Scope2.
