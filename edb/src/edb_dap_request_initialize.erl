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

-module(edb_dap_request_initialize).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-behaviour(edb_dap_request).

-export([parse_arguments/1, handle/2]).

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------

%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_Initialize
-type arguments() :: #{
    %% The ID of the client using this adapter
    clientID => binary(),
    %% The human-readable name of the client using this adapter
    clientName => binary(),
    %% The ID of the debug adapter
    adapterID := binary(),
    %% The ISO-639 locale of the client using this adapter, e.g. en-US or de-CH.
    locale => binary(),
    %% If true all line numbers are 1-based (default)
    linesStartAt1 => boolean(),
    %% If true all column numbers are 1-based (default).
    columnsStartAt1 => boolean(),
    %% Determines in what format paths are specified. The default is `path`, which
    %% is the native format.
    %% Values: 'path', 'uri', etc.
    pathFormat => path | uri,
    %% Client supports the `type` attribute for variables
    supportsVariableType => boolean(),
    %% Client supports the paging of variables
    supportsVariablePaging => boolean(),
    %% Client supports the `runInTerminal` request
    supportsRunInTerminalRequest => boolean(),
    %% Client supports memory references
    supportsMemoryReferences => boolean(),
    %% Client supports progress reporting
    supportsProgressReporting => boolean(),
    %% Client supports the `invalidated` event
    supportsInvalidatedEvent => boolean(),
    %%  Client supports the `memory` event
    supportsMemoryEvent => boolean(),
    %% Client supports the `argsCanBeInterpretedByShell` attribute on the
    %% `runInTerminal` request
    supportsArgsCanBeInterpretedByShell => boolean(),
    %%  Client supports the `startDebugging` request
    supportsStartDebuggingRequest => boolean(),
    %% The client will interpret ANSI escape sequences in the display of
    %% OutputEvent.output` and `Variable.value` fields when
    %% Capabilities.supportsANSIStyling` is also enabled
    supportsANSIStyling => boolean()
}.
-type capabilities() :: #{
    supportsConfigurationDoneRequest => boolean(),
    supportsFunctionBreakpoints => boolean(),
    supportsConditionalBreakpoints => boolean(),
    supportsHitConditionalBreakpoints => boolean(),
    supportsEvaluateForHovers => boolean(),
    exceptionBreakpointFilters => [exceptionBreakpointsFilter()],
    supportsStepBack => boolean(),
    supportsSetVariable => boolean(),
    supportsRestartFrame => boolean(),
    supportsGotoTargetsRequest => boolean(),
    supportsStepInTargetsRequest => boolean(),
    supportsCompletionsRequest => boolean(),
    completionTriggerCharacters => [binary()],
    supportsModulesRequest => boolean(),
    additionalModuleColumns => [columnDescriptor()],
    supportedChecksumAlgorithms => [edb_dap:checksumAlgorithm()],
    supportsRestartRequest => boolean(),
    supportsExceptionOptions => boolean(),
    supportsValueFormattingOptions => boolean(),
    supportsExceptionInfoRequest => boolean(),
    supportTerminateDebuggee => boolean(),
    supportSuspendDebuggee => boolean(),
    supportsDelayedStackTraceLoading => boolean(),
    supportsLoadedSourcesRequest => boolean(),
    supportsLogPoints => boolean(),
    supportsTerminateThreadsRequest => boolean(),
    supportsSetExpression => boolean(),
    supportsTerminateRequest => boolean(),
    supportsDataBreakpoints => boolean(),
    supportsReadMemoryRequest => boolean(),
    supportsWriteMemoryRequest => boolean(),
    supportsDisassembleRequest => boolean(),
    supportsCancelRequest => boolean(),
    supportsBreakpointLocationsRequest => boolean(),
    supportsClipboardContext => boolean(),
    supportsSteppingGranularity => boolean(),
    supportsInstructionBreakpoints => boolean(),
    supportsExceptionFilterOptions => boolean(),
    supportsSingleThreadExecutionRequests => boolean(),
    supportsDataBreakpointBytes => boolean(),
    breakpointModes => [breakpointMode()]
}.

-type breakpointMode() :: #{
    mode := binary(), label := binary(), description => binary(), appliesTo => [breakpointModeApplicability()]
}.
-type breakpointModeApplicability() :: source | exception | data | instruction.

-type columnDescriptor() :: #{
    attributeName := binary(),
    label := string(),
    format => binary(),
    type => string | number | boolean | unixTimestampUTC,
    width => number()
}.
-type exceptionBreakpointsFilter() :: #{
    filter := binary(),
    label := binary(),
    description => binary(),
    default => boolean(),
    supportsCondition => boolean(),
    conditionDescription => binary()
}.

-export_type([arguments/0, capabilities/0]).
-export_type([
    breakpointMode/0,
    breakpointModeApplicability/0,
    columnDescriptor/0,
    exceptionBreakpointsFilter/0
]).

%% ------------------------------------------------------------------
%% Behaviour implementation
%% ------------------------------------------------------------------
-spec parse_arguments(edb_dap:arguments()) -> {ok, arguments()}.
parse_arguments(Args) ->
    {ok, Args}.

-spec handle(State, Args) -> edb_dap_request:reaction(capabilities()) when
    State :: edb_dap_server:state(),
    Args :: arguments().
handle(#{state := started}, ClientInfo) ->
    Capabilities = capabilities(),
    #{
        response => #{success => true, body => Capabilities},
        state => #{state => initialized, client_info => ClientInfo}
    };
handle(_InvalidState, _Args) ->
    edb_dap_request:unexpected_request().

%% ------------------------------------------------------------------
%% Helpers
%% ------------------------------------------------------------------
-spec capabilities() -> capabilities().
capabilities() ->
    #{
        supportsConfigurationDoneRequest => false,
        supportsFunctionBreakpoints => false,
        supportsConditionalBreakpoints => false,
        supportsHitConditionalBreakpoints => false,
        supportsEvaluateForHovers => false,
        exceptionBreakpointFilters => [],
        supportsStepBack => false,
        supportsSetVariable => false,
        supportsRestartFrame => false,
        supportsGotoTargetsRequest => false,
        supportsStepInTargetsRequest => false,
        supportsCompletionsRequest => false,
        completionTriggerCharacters => [],
        supportsModulesRequest => false,
        additionalModuleColumns => [],
        supportedChecksumAlgorithms => [],
        supportsRestartRequest => false,
        supportsExceptionOptions => false,
        supportsValueFormattingOptions => false,
        supportsExceptionInfoRequest => false,
        supportTerminateDebuggee => false,
        supportSuspendDebuggee => false,
        supportsDelayedStackTraceLoading => false,
        supportsLoadedSourcesRequest => false,
        supportsLogPoints => false,
        supportsTerminateThreadsRequest => false,
        supportsSetExpression => false,
        supportsTerminateRequest => false,
        supportsDataBreakpoints => false,
        supportsReadMemoryRequest => false,
        supportsWriteMemoryRequest => false,
        supportsDisassembleRequest => false,
        supportsCancelRequest => false,
        supportsBreakpointLocationsRequest => false,
        supportsClipboardContext => false,
        supportsSteppingGranularity => false,
        supportsInstructionBreakpoints => false,
        supportsExceptionFilterOptions => false,
        supportsSingleThreadExecutionRequests => false,
        supportsDataBreakpointBytes => false,
        breakpointModes => []
    }.
