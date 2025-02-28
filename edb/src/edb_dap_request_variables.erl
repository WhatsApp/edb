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

-module(edb_dap_request_variables).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-behaviour(edb_dap_request).

-export([parse_arguments/1, handle/2]).

-include_lib("kernel/include/logger.hrl").

-define(MAX_TERM_SIZE, 1_000_000).

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------

%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_Variables
-type arguments() :: #{
    % The variable for which to retrieve its children. The `variablesReference`
    % must have been obtained in the current suspended state.
    variablesReference := number(),
    % Filter to limit the child variables to either named or indexed. If omitted,
    % both types are fetched.
    % Possible values: 'indexed', 'named'
    filter => binary(),
    % The index of the first variable to return; if omitted children start at 0.
    % The attribute is only honored by a debug adapter if the corresponding
    % capability `supportsVariablePaging` is true.
    start => number(),
    % The number of variables to return. If count is missing or 0, all variables
    % are returned.
    % The attribute is only honored by a debug adapter if the corresponding
    % capability `supportsVariablePaging` is true.
    count => number(),
    % Specifies details on how to format the Variable values.
    % The attribute is only honored by a debug adapter if the corresponding
    % capability `supportsValueFormattingOptions` is true.
    format => value_format()
}.

-type value_format() :: #{
    % Display the value in hex
    hex => boolean()
}.

-type response_body() ::
    #{
        %  All (or a range) of variables for the given variable reference.
        variables := [variable()]
    }.

-type variable() :: #{
    % The variable's name.
    name := binary(),
    % The variable's value.
    % This can be a multi-line text, e.g. for a function the body of a function.
    % For structured variables (which do not have a simple value), it is
    % recommended to provide a one-line representation of the structured object.
    % This helps to identify the structured object in the collapsed state when
    % its children are not yet visible.
    % An empty string can be used if no value should be shown in the UI.
    value := binary(),
    % The type of the variable's value. Typically shown in the UI when hovering
    % over the value.
    % This attribute should only be returned by a debug adapter if the
    % corresponding capability `supportsVariableType` is true.
    type => binary(),
    % Properties of a variable that can be used to determine how to render the
    % variable in the UI.
    presentationHint => variable_presentation_hint(),
    % The evaluatable name of this variable which can be passed to the `evaluate`
    % request to fetch the variable's value.
    evaluateName => binary(),
    % If `variablesReference` is > 0, the variable is structured and its children
    % can be retrieved by passing `variablesReference` to the `variables` request
    % as long as execution remains suspended.
    variablesReference := number(),
    % The number of named child variables.
    % The client can use this information to present the children in a paged UI
    % and fetch them in chunks.
    namedVariables => number(),
    % The number of indexed child variables.
    % The client can use this information to present the children in a paged UI
    % and fetch them in chunks.
    indexedVariables => number(),
    % A memory reference associated with this variable.
    % For pointer type variables, this is generally a reference to the memory
    % address contained in the pointer.
    % For executable data, this reference may later be used in a `disassemble`
    % request.
    % This attribute may be returned by a debug adapter if corresponding
    % capability `supportsMemoryReferences` is true.
    memoryReference => binary(),
    % A reference that allows the client to request the location where the
    % variable is declared. This should be present only if the adapter is likely
    % to be able to resolve the location.
    % This reference shares the same lifetime as the `variablesReference`.
    declarationLocationReference => number(),
    % A reference that allows the client to request the location where the
    % variable's value is declared. For example, if the variable contains a
    % function pointer, the adapter may be able to look up the function's
    % location. This should be present only if the adapter is likely to be able
    % to resolve the location.
    % This reference shares the same lifetime as the `variablesReference`.
    valueLocationReference => number()
}.
-type variable_presentation_hint() :: #{
    % The kind of variable. Before introducing additional values, try to use the
    % listed values.
    % Values:
    % 'property': Indicates that the object is a property.
    % 'method': Indicates that the object is a method.
    % 'class': Indicates that the object is a class.
    % 'data': Indicates that the object is data.
    % 'event': Indicates that the object is an event.
    % 'baseClass': Indicates that the object is a base class.
    % 'innerClass': Indicates that the object is an inner class.
    % 'interface': Indicates that the object is an interface.
    % 'mostDerivedClass': Indicates that the object is the most derived class.
    % 'virtual': Indicates that the object is virtual, that means it is a
    % synthetic object introduced by the adapter for rendering purposes, e.g. an
    % index range for large arrays.
    % 'dataBreakpoint': Deprecated: Indicates that a data breakpoint is
    % registered for the object. The `hasDataBreakpoint` attribute should
    % generally be used instead.
    % etc.
    kind => binary(),
    % Set of attributes represented as an array of strings. Before introducing
    % additional values, try to use the listed values.
    % Values:
    % 'static': Indicates that the object is static.
    % 'constant': Indicates that the object is a constant.
    % 'readOnly': Indicates that the object is read only.
    % 'rawString': Indicates that the object is a raw string.
    % 'hasObjectId': Indicates that the object can have an Object ID created for
    % it. This is a vestigial attribute that is used by some clients; 'Object
    % ID's are not specified in the protocol.
    % 'canHaveObjectId': Indicates that the object has an Object ID associated
    % with it. This is a vestigial attribute that is used by some clients;
    % 'Object ID's are not specified in the protocol.
    % 'hasSideEffects': Indicates that the evaluation had side effects.
    % 'hasDataBreakpoint': Indicates that the object has its value tracked by a
    % data breakpoint.
    % etc.
    attributes => [binary()],
    % Visibility of variable. Before introducing additional values, try to use
    % the listed values.
    % Values: 'public', 'private', 'protected', 'internal', 'final', etc.
    visibility => binary(),
    % If true, clients can present the variable with a UI that supports a
    % specific gesture to trigger its evaluation.
    % This mechanism can be used for properties that require executing code when
    % retrieving their value and where the code execution can be expensive and/or
    % produce side-effects. A typical example are properties based on a getter
    % function.
    % Please note that in addition to the `lazy` flag, the variable's
    % `variablesReference` is expected to refer to a variable that will provide
    % the value through another `variable` request.
    lazy => boolean()
}.

-export_type([arguments/0, response_body/0, variable/0, value_format/0, variable_presentation_hint/0]).

%% ------------------------------------------------------------------
%% Behaviour implementation
%% ------------------------------------------------------------------
-spec parse_arguments(edb_dap:arguments()) -> {ok, arguments()}.
parse_arguments(Args) ->
    {ok, Args}.

-spec handle(State, Args) -> edb_dap_request:reaction(response_body()) when
    State :: edb_dap_state:t(),
    Args :: arguments().
handle(State, #{variablesReference := VariablesReference}) ->
    case edb_dap_id_mappings:var_reference_to_frame_scope(VariablesReference) of
        {ok, #{frame := FrameId, scope := Scope}} ->
            case edb_dap_id_mappings:frame_id_to_pid_frame(FrameId) of
                {ok, #{pid := Pid, frame_no := FrameNo}} ->
                    case Scope of
                        messages ->
                            #{target_node := #{name := Node}} = edb_dap_state:get_context(State),
                            % elp:ignore W0014 (cross_node_eval)
                            case erpc:call(Node, erlang, process_info, [Pid, messages]) of
                                {messages, Messages0} when is_list(Messages0) ->
                                    % Ideally we'd have a `erl_debugger:peek_message/1` function
                                    % which would allow us to peek at the message queue and return
                                    % a too_large entry if the message is too large.
                                    Messages = [cap_by_size(M, ?MAX_TERM_SIZE) || M <- Messages0],
                                    #{
                                        response => #{
                                            success => true,
                                            body => #{
                                                variables => unnamed_variables(~"", Messages)
                                            }
                                        }
                                    };
                                _ ->
                                    ?LOG_WARNING("Cannot resolve messages for pid ~p and frame_no ~p", [Pid, FrameNo]),
                                    throw(~"Cannot resolve messages")
                            end;
                        _ ->
                            case edb:stack_frame_vars(Pid, FrameNo, ?MAX_TERM_SIZE) of
                                not_paused ->
                                    ?LOG_WARNING("Cannot resolve variables (not_paused) for pid ~p and frame_no ~p", [
                                        Pid, FrameNo
                                    ]),
                                    throw(~"Cannot resolve variables (not_paused)");
                                undefined ->
                                    ?LOG_WARNING("Cannot resolve variables (undefined) for pid ~p and frame_no ~p", [
                                        Pid, FrameNo
                                    ]),
                                    throw(~"Cannot resolve variables (undefined)");
                                {ok, Result} ->
                                    Variables =
                                        case Scope of
                                            locals ->
                                                [variable(Name, Value) || Name := Value <- maps:get(vars, Result, #{})];
                                            registers ->
                                                XRegs = unnamed_variables(~"X", maps:get(xregs, Result, [])),
                                                YRegs = unnamed_variables(~"Y", maps:get(yregs, Result, [])),
                                                XRegs ++ YRegs
                                        end,
                                    #{
                                        response => #{
                                            success => true,
                                            body => #{
                                                variables => Variables
                                            }
                                        }
                                    }
                            end
                    end;
                {error, not_found} ->
                    ?LOG_WARNING("Cannot find pid_frame for frame ~p", [FrameId]),
                    throw(~"Cannot resolve variables (variable_ref_not_found)")
            end;
        {error, not_found} ->
            ?LOG_WARNING("Cannot find frame for variables reference ~p", [VariablesReference]),
            throw(~"Cannot resolve variables (frame_id_not_found)")
    end.

%% ------------------------------------------------------------------
%% Helpers
%% ------------------------------------------------------------------
-spec cap_by_size(term(), non_neg_integer()) -> edb:value().
cap_by_size(Term, MaxSize) ->
    Size = erts_debug:flat_size(Term),
    case Size > MaxSize of
        true ->
            {too_large, Size, MaxSize};
        false ->
            {value, Term}
    end.

-spec variable(binary(), edb:value()) -> variable().
variable(Name, Value) ->
    #{
        name => Name,
        value => variable_value(Value),
        variablesReference => 0
    }.

-spec unnamed_variables(binary(), [edb:value()]) -> [variable()].
unnamed_variables(Prefix, Values) ->
    Fun = fun(Value, {Acc, Count}) ->
        Name = edb:format("~s~p", [Prefix, Count]),
        {[variable(Name, Value) | Acc], Count + 1}
    end,
    {Registers, _Count} = lists:foldl(Fun, {[], 0}, Values),
    lists:reverse(Registers).

-spec variable_value(edb:value()) -> binary().
variable_value({too_large, Size, Max}) ->
    edb_dap:to_binary(io_lib:format("Too Large (~p vs ~p)", [Size, Max]));
variable_value({value, Value}) ->
    edb:format("~p", [Value]).
