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

-module(edb_dap_event).

-oncall("whatsapp_server_devx").
-moduledoc """
DAP Events
""".
-compile(warn_missing_spec_all).

-export([
    exited/1,
    initialized/0,
    output/1,
    stopped/1,
    terminated/0
]).

%%%---------------------------------------------------------------------------------
%%% Types
%%%---------------------------------------------------------------------------------

-type event() :: event(edb_dap:body()).

-type event(T) :: #{
    event := edb_dap:event_type(),
    body => T
}.
-export_type([event/0, event/1]).

-export_type([exited_body/0]).
-export_type([output_body/0]).
-export_type([stopped_body/0]).
-export_type([terminated_body/0]).

%%%---------------------------------------------------------------------------------
%%% Exited event
%%%---------------------------------------------------------------------------------
%% https://microsoft.github.io/debug-adapter-protocol/specification#Events_Exited
-type exited_body() :: #{
    % The exit code returned from the debuggee.
    exitCode := number()
}.

-spec exited(ExitCode :: number()) -> event(exited_body()).
exited(ExitCode) ->
    #{event => ~"exited", body => #{exitCode => ExitCode}}.

%%%---------------------------------------------------------------------------------
%%% Initialized event
%%%---------------------------------------------------------------------------------
%% https://microsoft.github.io/debug-adapter-protocol/specification#Events_Initialized
-spec initialized() -> event().
initialized() ->
    #{event => ~"initialized"}.

%%%---------------------------------------------------------------------------------
%%% Output event
%%%---------------------------------------------------------------------------------
%% https://microsoft.github.io/debug-adapter-protocol/specification#Events_Output

-type output_body() :: #{
    % The output category. If not specified or if the category is
    % not understood by the client, `console` is assumed.
    category => console | important | stdout | stderr | telemetry | binary(),

    % The output to report.
    output := binary(),

    % Support for keeping an output log organized by grouping related messages.
    % Values:
    %   'start': Start a new group in expanded mode. Subsequent output events are
    %     members of the group and should be shown indented. The `output` attribute
    %     becomes the name of the group and is not indented.
    %   'startCollapsed': Start a new group in collapsed mode. Subsequent output
    %     events are members of the group and should be shown indented (as soon as
    %     the group is expanded). The `output` attribute becomes the name of the
    %     group and is not indented.
    %   'end': End the current group and decrease the indentation of subsequent
    %     output events.
    group => 'start' | 'startCollapsed' | 'end',

    % If an attribute `variablesReference` exists and its value is > 0, the
    % output contains objects which can be retrieved by passing the value to the
    % `variables` request as long as execution remains suspended. See 'Lifetime
    % of Object References' in the Overview section for details.
    variablesReference => number(),

    % The source location where the output was produced.
    source => edb_dap:body(),

    % The source location's line where the output was produced.
    line => number(),

    % The position of the first character of the output produced in the source
    % location's line.
    column => number(),

    % Additional data to report. For the `telemetry` category the data is sent
    % to telemetry, for the other categories the data is shown in JSON format.
    data => edb_dap:body()
}.

-spec output(Body) -> event(Body) when Body :: output_body().
output(Body) ->
    #{event => ~"output", body => Body}.

%%%---------------------------------------------------------------------------------
%%% Stopped event
%%%---------------------------------------------------------------------------------
%% https://microsoft.github.io/debug-adapter-protocol/specification#Events_Stopped
-type stopped_body() :: #{
    % The reason for the event.
    % For backward compatibility this string is shown in the UI if the
    % `description` attribute is missing (but it must not be translated).
    % Values: 'step', 'breakpoint', 'exception', 'pause', 'entry', 'goto',
    % 'function breakpoint', 'data breakpoint', 'instruction breakpoint', etc.
    reason := binary(),

    % The full reason for the event, e.g. 'Paused on exception'. This string is
    % shown in the UI as is and can be translated.
    description => binary(),

    % The thread which was stopped.
    threadId => number(),

    % A value of true hints to the client that this event should not change the
    % focus.
    preserveFocusHint => boolean(),

    % Additional information. E.g. if reason is `exception`, text contains the
    % exception name. This string is shown in the UI.
    text => binary(),

    % If `allThreadsStopped` is true, a debug adapter can announce that all
    % threads have stopped.
    % - The client should use this information to enable that all threads can
    % be expanded to access their stacktraces.
    % - If the attribute is missing or false, only the thread with the given
    % `threadId` can be expanded.
    allThreadsStopped => boolean(),

    % Ids of the breakpoints that triggered the event. In most cases there is
    % only a single breakpoint but here are some examples for multiple
    % breakpoints:
    % - Different types of breakpoints map to the same location.
    % - Multiple source breakpoints get collapsed to the same instruction by
    % the compiler/runtime.
    % - Multiple function breakpoints with different function names map to the
    % same location.
    hitBreakpointIds => [number()]
}.
-spec stopped(Body) -> event(Body) when Body :: stopped_body().
stopped(Body) ->
    #{event => ~"stopped", body => Body}.

%%%---------------------------------------------------------------------------------
%%% Terminated event
%%%---------------------------------------------------------------------------------
%% https://microsoft.github.io/debug-adapter-protocol/specification#Events_Terminated
-type terminated_body() ::
    none()
    | #{
        % A debug adapter may set `restart` to true (or to an arbitrary object) to
        % request that the client restarts the session.
        % The value is not interpreted by the client and passed unmodified as an
        % attribute `__restart` to the `launch` and `attach` requests.
        restart => true | edb_dap:arguments()
    }.

-spec terminated() -> event(terminated_body()).
terminated() ->
    #{event => ~"terminated"}.
