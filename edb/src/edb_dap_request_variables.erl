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

-export([value_format_template/0]).
-export([scope_variables_ref/3, structure_variables_ref/2]).

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------

-type variables_reference() :: number().

%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_Variables
-type arguments() :: #{
    % The variable for which to retrieve its children. The `variablesReference`
    % must have been obtained in the current suspended state.
    variablesReference := variables_reference(),
    % Filter to limit the child variables to either named or indexed. If omitted,
    % both types are fetched.
    % Possible values: 'indexed', 'named'
    filter => indexed | named,
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
        % All (or a range) of variables for the given variable reference.
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
    variablesReference := variables_reference(),
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
    kind =>
        'property'
        | 'method'
        | 'class'
        | 'data'
        | 'event'
        | 'baseClass'
        | 'innerClass'
        | 'interface'
        | 'mostDerivedClass'
        | 'virtual'
        | 'dataBreakpoint',
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
    attributes => [
        'static'
        | 'constant'
        | 'readOnly'
        | 'rawString'
        | 'hasObjectId'
        | 'canHaveObjectId'
        | 'hasSideEffects'
        | 'hasDataBreakpoint'
    ],
    % Visibility of variable. Before introducing additional values, try to use
    % the listed values.
    % Values: 'public', 'private', 'protected', 'internal', 'final', etc.
    visibility =>
        'public' | 'private' | 'protected' | 'internal' | 'final',
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

-export_type([arguments/0, response_body/0]).
-export_type([variables_reference/0, variable/0, value_format/0, variable_presentation_hint/0]).

-spec value_format_template() -> edb_dap_parse:template().
value_format_template() ->
    #{
        hex => {optional, edb_dap_parse:boolean()}
    }.

-spec arguments_template() -> edb_dap_parse:template().
arguments_template() ->
    #{
        variablesReference => edb_dap_parse:number(),
        filter => {optional, edb_dap_parse:atoms([indexed, named])},
        start => {optional, edb_dap_parse:number()},
        count => {optional, edb_dap_parse:number()},
        format => {optional, value_format_template()}
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
handle(#{state := attached, client_info := ClientInfo}, Args = #{variablesReference := VariablesReference}) ->
    Window = get_requested_window(Args),
    case variables_reference_to_vars_info(VariablesReference) of
        #{type := scope, vars := Variables} ->
            Slice = edb_dap_eval_delegate:slice_list(Variables, Window),
            #{response => edb_dap_request:success(#{variables => Slice})};
        #{type := structure, frame_id := FrameId, accessor := Accessor, evaluate_name := EvalName} ->
            handle_structure(ClientInfo, FrameId, Accessor, EvalName, Window)
    end;
handle(_UnexpectedState, _) ->
    edb_dap_request:unexpected_request().

-spec handle_structure(ClientInfo, FrameId, Accessor, EvalName, Window) ->
    edb_dap_request:reaction(response_body())
when
    ClientInfo :: edb_dap_server:client_info(),
    FrameId :: edb_dap_id_mappings:id(),
    Accessor :: edb_dap_eval_delegate:accessor(),
    EvalName :: edb_dap_eval_delegate:eval_name(),
    Window :: edb_dap_eval_delegate:window().
handle_structure(ClientInfo, FrameId, Accessor, EvalName, Window) ->
    {ok, #{pid := Pid, frame_no := FrameNo}} = edb_dap_id_mappings:frame_id_to_pid_frame(FrameId),
    EvalResult = edb_dap_eval_delegate:eval(#{
        context => {Pid, FrameNo},
        function => edb_dap_eval_delegate:structure_callback(Accessor, EvalName, Window)
    }),
    case EvalResult of
        not_paused ->
            edb_dap_request:not_paused(Pid);
        undefined ->
            throw({failed_to_resolve_scope, #{pid => Pid, frame_no => FrameNo}});
        {ok, RawVars} ->
            Vars = make_variables(ClientInfo, FrameId, RawVars),
            #{response => edb_dap_request:success(#{variables => Vars})};
        {eval_error, Error} ->
            throw({failed_to_eval_structure, Error})
    end.

%% ------------------------------------------------------------------
%% Variables references
%% ------------------------------------------------------------------
-spec scope_variables_ref(ClientInfo, FrameId, Scope) -> edb_dap_request_variables:variables_reference() when
    ClientInfo :: edb_dap_server:client_info(),
    FrameId :: edb_dap_id_mappings:id(),
    Scope :: edb_dap_eval_delegate:scope().
scope_variables_ref(ClientInfo, FrameId, #{type := Type, variables := RawVars}) ->
    Vars = make_variables(ClientInfo, FrameId, RawVars),
    edb_dap_id_mappings:vars_info_to_vars_ref(#{
        type => scope,
        scope => Type,
        frame_id => FrameId,
        vars => Vars
    }).

-spec structure_variables_ref(FrameId, Structure) -> variables_reference() when
    FrameId :: edb_dap_id_mappings:id(),
    Structure :: none | edb_dap_eval_delegate:structure().
structure_variables_ref(_FrameId, none) ->
    0;
structure_variables_ref(FrameId, Structure) ->
    VarsInfo = Structure#{
        type => structure,
        frame_id => FrameId
    },
    edb_dap_id_mappings:vars_info_to_vars_ref(VarsInfo).

%% ------------------------------------------------------------------
%% Helpers
%% ------------------------------------------------------------------
-spec make_variables(ClientInfo, FrameId, RawVars) -> [variable()] when
    ClientInfo :: edb_dap_server:client_info(),
    FrameId :: edb_dap_id_mappings:id(),
    RawVars :: [edb_dap_eval_delegate:variable()].
make_variables(ClientInfo, FrameId, RawVars) ->
    [
        maybe_add_pagination_info(
            ClientInfo,
            Structure,
            maybe_add_evaluate_name(Structure, #{
                name => Name,
                value => Rep,
                variablesReference => structure_variables_ref(FrameId, Structure)
            })
        )
     || #{name := Name, value_rep := Rep, structure := Structure} <- RawVars
    ].

-spec maybe_add_pagination_info(ClientInfo, Structure, Variable) -> Variable when
    ClientInfo :: edb_dap_server:client_info(),
    Structure :: none | edb_dap_eval_delegate:structure(),
    Variable :: variable().
maybe_add_pagination_info(#{supportsVariablePaging := true}, #{count := N}, Variable) when N > 0 ->
    Variable#{indexedVariables => N};
maybe_add_pagination_info(_ClientInfo, _Structure, Variable) ->
    Variable.

-spec maybe_add_evaluate_name(Structure, Variable) -> Variable when
    Structure :: none | edb_dap_eval_delegate:structure(),
    Variable :: variable().
maybe_add_evaluate_name(#{evaluate_name := EvalName}, Variable) when is_binary(EvalName) ->
    Variable#{evaluateName => EvalName};
maybe_add_evaluate_name(_, Variable) ->
    Variable.

-spec variables_reference_to_vars_info(VarRef) -> edb_dap_id_mappings:vars_info() when
    VarRef :: edb_dap_id_mappings:id().
variables_reference_to_vars_info(VarRef) ->
    case edb_dap_id_mappings:vars_reference_to_vars_info(VarRef) of
        {ok, VarsInfo} -> VarsInfo;
        {error, not_found} -> edb_dap_request:abort(edb_dap_request:unknown_resource(variables_ref, VarRef))
    end.

-spec get_requested_window(Args) -> edb_dap_eval_delegate:window() when
    Args :: arguments().
get_requested_window(Args) ->
    #{
        start => maps:get(start, Args, 0) + 1,
        count => maps:get(count, Args, infinity)
    }.
