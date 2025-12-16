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

-module(edb_dap_request_evaluate).

-moduledoc """
Handles Debug Adapter Protocol (DAP) evaluate requests for the Erlang debugger.

The module follows the Microsoft Debug Adapter Protocol specification for
evaluate requests: https://microsoft.github.io/debug-adapter-protocol/specification#Requests_Evaluate
""".

%% erlfmt:ignore
% @fb-only[end= ]: -oncall("whatsapp_server_devx").
-compile(warn_missing_spec_all).

-behaviour(edb_dap_request).

-export([parse_arguments/1, handle/2]).

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------
%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_Evaluate
-type arguments() :: #{
    % The expression to evaluate.
    expression := binary(),

    % Evaluate the expression in the scope of this stack frame. If not specified,
    % the expression is evaluated in the global scope.
    frameId => number(),

    % The contextual line where the expression should be evaluated. In the
    % 'hover' context, this should be set to the start of the expression being
    % hovered.
    line => number(),

    % The contextual column where the expression should be evaluated. This may be
    % provided if `line` is also provided.
    %
    % It is measured in UTF-16 code units and the client capability
    % `columnsStartAt1` determines whether it is 0- or 1-based.
    column => number(),

    % The contextual source in which the `line` is found. This must be provided
    % if `line` is provided.
    source => edb_dap:source(),

    % The context in which the evaluate request is used.
    % Values:
    % 'watch': evaluate is called from a watch view context.
    % 'repl': evaluate is called from a REPL context.
    % 'hover': evaluate is called to generate the debug hover contents.
    % This value should only be used if the corresponding capability
    % `supportsEvaluateForHovers` is true.
    % 'clipboard': evaluate is called to generate clipboard contents.
    % This value should only be used if the corresponding capability
    % `supportsClipboardContext` is true.
    % 'variables': evaluate is called from a variables view context.
    % etc.
    context => 'watch' | 'repl' | 'hover' | 'clipboard' | 'variables' | atom(),

    % Specifies details on how to format the result.
    % The attribute is only honored by a debug adapter if the corresponding
    % capability `supportsValueFormattingOptions` is true.
    format => edb_dap_request_variables:value_format()
}.

-type response_body() :: #{
    % The result of the evaluate request.
    result := binary(),

    % The type of the evaluate result.
    % This attribute should only be returned by a debug adapter if the
    % corresponding capability `supportsVariableType` is true.
    type => binary(),

    % Properties of an evaluate result that can be used to determine how to
    % render the result in the UI.
    presentationHint => edb_dap_request_variables:variable_presentation_hint(),

    % If `variablesReference` is > 0, the evaluate result is structured and its
    % children can be retrieved by passing `variablesReference` to the
    % `variables` request as long as execution remains suspended. See 'Lifetime
    % of Object References' in the Overview section for details.
    variablesReference := number(),

    % The number of named child variables.
    % The client can use this information to present the variables in a paged
    % UI and fetch them in chunks.
    % The value should be less than or equal to 2147483647 (2^31-1).
    namedVariables => number(),

    % The number of indexed child variables.
    % The client can use this information to present the variables in a paged
    % UI and fetch them in chunks.
    % The value should be less than or equal to 2147483647 (2^31-1).
    indexedVariables => number(),

    % A memory reference to a location appropriate for this result.
    % For pointer type eval results, this is generally a reference to the
    % memory address contained in the pointer.
    % This attribute may be returned by a debug adapter if corresponding
    % capability `supportsMemoryReferences` is true.
    memoryReference => binary(),

    % A reference that allows the client to request the location where the
    % returned value is declared. For example, if a function pointer is
    % returned, the adapter may be able to look up the function's location.
    % This should be present only if the adapter is likely to be able to
    % resolve the location.
    %
    % This reference shares the same lifetime as the `variablesReference`. See
    % 'Lifetime of Object References' in the Overview section for details.
    valueLocationReference => number()
}.

-export_type([arguments/0, response_body/0]).

-spec arguments_template() -> edb_dap_parse:template().
arguments_template() ->
    #{
        expression => edb_dap_parse:binary(),
        frameId => {optional, edb_dap_parse:number()},
        line => {optional, edb_dap_parse:number()},
        column => {optional, edb_dap_parse:number()},
        source => {optional, edb_dap_request_set_breakpoints:source_template()},
        context => {optional, edb_dap_parse:atom()},
        format => {optional, edb_dap_request_variables:value_format_template()}
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
handle(#{state := attached, client_info := ClientInfo}, Args = #{expression := Expr, frameId := FrameId}) ->
    {ok, #{pid := Pid, frame_no := FrameNo}} = edb_dap_id_mappings:frame_id_to_pid_frame(FrameId),
    maybe
        {ok, StackFrameVars} ?= edb:stack_frame_vars(Pid, FrameNo, 0),
        FreeVars = maps:keys(maps:get(vars, StackFrameVars, #{})),
        Line = maps:get(line, Args, 1),
        Col = maps:get(column, Args, 1),
        {ok, CompiledExpr} ?=
            case edb_expr:compile_expr(Expr, #{free_vars => FreeVars, start_line => Line, start_col => Col}) of
                {error, CompileErr} -> {compile_error, CompileErr};
                CompileRes = {ok, _} -> CompileRes
            end,
        Fmt =
            case maps:get(context, Args, unknown) of
                clipboard -> format_full;
                _ -> format_short
            end,
        {ok, EvalResult} ?=
            edb_dap_eval_delegate:eval(#{
                context => {Pid, FrameNo},
                function => edb_dap_eval_delegate:evaluate_callback(Expr, CompiledExpr, Fmt)
            }),
        case EvalResult of
            #{type := exception, class := Class, reason := Reason, stacktrace := _ST} ->
                edb_dap_request:precondition_violation(format_exception(Class, Reason));
            #{type := success, value_rep := Rep, structure := Structure} ->
                Body = #{
                    result => Rep,
                    variablesReference => edb_dap_request_variables:structure_variables_ref(FrameId, Structure)
                },
                #{response => edb_dap_request:success(maybe_add_pagination_info(ClientInfo, Structure, Body))}
        end
    else
        not_paused -> edb_dap_request:not_paused(Pid);
        undefined -> throw({failed_to_resolve_scope, #{pid => Pid, frame_no => FrameNo}});
        {compile_error, CompileError} -> edb_dap_request:precondition_violation(format_compile_error(CompileError));
        {eval_error, EvalError} -> throw({failed_to_evaluate, EvalError})
    end.

%% ------------------------------------------------------------------
%% Helpers
%% ------------------------------------------------------------------

-spec format_compile_error(Error) -> io_lib:chars() when
    Error :: edb_expr:compile_error().
format_compile_error({Loc, Module, Descriptor}) ->
    io_lib:format("~s:~s", [format_location(Loc), Module:format_error(Descriptor)]).

-spec format_location(Location) -> io_lib:chars() when
    Location :: none | erl_anno:location().
format_location(none) ->
    "";
format_location(Line) when is_integer(Line) ->
    integer_to_list(Line);
format_location({Line, Col}) when is_integer(Line), is_integer(Col) ->
    io_lib:format("~b:~b", [Line, Col]).

-spec format_exception(Class, Reason) -> binary() when
    Class :: error | exit | throw,
    Reason :: term().
format_exception(Class, Reason) ->
    ExceptionStr = io_lib:format("Uncaught exception -- ~p:~p", [Class, Reason]),
    list_to_binary(ExceptionStr).

-spec maybe_add_pagination_info(ClientInfo, Structure, ResponseBody) -> ResponseBody when
    ClientInfo :: edb_dap_server:client_info(),
    Structure :: none | edb_dap_eval_delegate:structure(),
    ResponseBody :: response_body().
maybe_add_pagination_info(#{supportsVariablePaging := true}, #{count := N}, Body) when N > 0 ->
    Body#{indexedVariables => N};
maybe_add_pagination_info(_ClientInfo, _Structure, Body) ->
    Body.
