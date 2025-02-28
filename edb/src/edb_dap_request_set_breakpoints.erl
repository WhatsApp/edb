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

-module(edb_dap_request_set_breakpoints).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-behaviour(edb_dap_request).

-export([parse_arguments/1, handle/2]).

-include_lib("kernel/include/logger.hrl").

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------

%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_SetBreakpoints
-type arguments() :: #{
    %% The source location of the breakpoints; either `source.path` or
    %% `source.sourceReference` must be specified.
    source := edb_dap:source(),

    %% The code locations of the breakpoints.
    breakpoints => [sourceBreakpoint()],

    % Deprecated
    lines => [number()],

    %% A value of true indicates that the underlying source has been modified
    %% which results in new breakpoint locations.
    sourceModified => boolean()
}.
-type breakpoints() :: #{breakpoints := [breakpoint()]}.
-type breakpoint() :: #{
    %% The identifier for the breakpoint. It is needed if breakpoint events are
    %% used to update or remove breakpoints.
    id => number(),

    %% If true, the breakpoint could be set (but not necessarily at the desired
    %% location.
    verified := boolean(),

    %% A message about the state of the breakpoint.
    %% This is shown to the user and can be used to explain why a breakpoint could
    %% not be verified.
    message => binary(),

    %% The source where the breakpoint is located.
    source => edb_dap:source(),

    %% The start line of the actual range covered by the breakpoint.
    line => number(),

    %% Start position of the source range covered by the breakpoint. It is
    %% measured in UTF-16 code units and the client capability `columnsStartAt1`
    %% determines whether it is 0- or 1-based.
    column => number(),

    %% The end line of the actual range covered by the breakpoint.
    endLine => number(),

    %% End position of the source range covered by the breakpoint. It is measured
    %% in UTF-16 code units and the client capability `columnsStartAt1` determines
    %% whether it is 0- or 1-based.
    %% If no end line is given, then the end column is assumed to be in the start
    %% line.
    endColumn => number(),

    %% A memory reference to where the breakpoint is set.
    instructionReference => binary(),

    %% The offset from the instruction reference.
    %% This can be negative.
    offset => number(),

    %%  A machine-readable explanation of why a breakpoint may not be verified. If
    %% a breakpoint is verified or a specific reason is not known, the adapter
    %% should omit this property. Possible values include:
    %%
    %% - `pending`: Indicates a breakpoint might be verified in the future, but
    %% the adapter cannot verify it in the current state.
    %% - `failed`: Indicates a breakpoint was not able to be verified, and the
    %% adapter does not believe it can be verified without intervention.
    %% Values: 'pending', 'failed'
    reason => binary()
}.
-type sourceBreakpoint() :: #{
    %% The source line of the breakpoint or logpoint.
    line := number(),

    %% Start position within source line of the breakpoint or logpoint. It is
    %% measured in UTF-16 code units and the client capability `columnsStartAt1`
    %% determines whether it is 0- or 1-based.
    column => number(),

    %% The expression for conditional breakpoints.
    %% It is only honored by a debug adapter if the corresponding capability
    %% `supportsConditionalBreakpoints` is true.
    condition => binary(),

    %% The expression that controls how many hits of the breakpoint are ignored.
    %% The debug adapter is expected to interpret the expression as needed.
    %% The attribute is only honored by a debug adapter if the corresponding
    %% capability `supportsHitConditionalBreakpoints` is true.
    %% If both this property and `condition` are specified, `hitCondition` should
    %% be evaluated only if the `condition` is met, and the debug adapter should
    %% stop only if both conditions are met.
    hitCondition => binary(),

    %% If this attribute exists and is non-empty, the debug adapter must not
    %% 'break' (stop)
    %% but log the message instead. Expressions within `{}` are interpolated.
    %% The attribute is only honored by a debug adapter if the corresponding
    %% capability `supportsLogPoints` is true.
    %% If either `hitCondition` or `condition` is specified, then the message
    %% should only be logged if those conditions are met.
    logMessage => binary(),

    %% The mode of this breakpoint. If defined, this must be one of the
    %% `breakpointModes` the debug adapter advertised in its `Capabilities`.
    mode => binary()
}.
-export_type([arguments/0, breakpoints/0]).
-export_type([breakpoint/0, sourceBreakpoint/0]).

%% ------------------------------------------------------------------
%% Behaviour implementation
%% ------------------------------------------------------------------
-spec parse_arguments(edb_dap:arguments()) -> {ok, arguments()}.
parse_arguments(Args) ->
    {ok, Args}.

-spec handle(State, Args) -> edb_dap_request:reaction(breakpoints()) when
    State :: edb_dap_server:state(),
    Args :: arguments().
handle(State, Args = #{source := #{path := Path}}) ->
    Module = binary_to_atom(filename:basename(Path, ".erl")),

    % TODO(T202772655): Remove once edb:set_breakpoint/2 takes care of auto-loading modules
    #{context := #{target_node := #{name := Node}}} = State,
    % elp:ignore W0014 (cross_node_eval)
    erpc:call(Node, code, ensure_loaded, [Module]),

    SourceBreakpoints = maps:get(breakpoints, Args, []),
    SourceBreakpointLines = [Line || #{line := Line} <- SourceBreakpoints],

    LineResults = edb:set_breakpoints(Module, SourceBreakpointLines),

    Breakpoints = lists:map(
        fun({Line, Result}) ->
            case Result of
                ok ->
                    #{line => Line, verified => true};
                {error, Reason} ->
                    ?LOG_WARNING("Failed to set breakpoint: ~p, ~p, ~p", [Module, Line, Reason]),
                    Message = edb:format("~p", [Reason]),
                    #{line => Line, verified => false, message => Message, reason => <<"failed">>}
            end
        end,
        LineResults
    ),
    Body = #{breakpoints => Breakpoints},
    #{response => #{success => true, body => Body}}.
