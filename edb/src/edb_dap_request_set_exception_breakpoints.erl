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

-module(edb_dap_request_set_exception_breakpoints).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-behaviour(edb_dap_request).

-export([parse_arguments/1, handle/2]).

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------
%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_SetExceptionBreakpoints
%%% Notice that, since , the arguments for this request are
%%% not part of the DAP specification itself.

-export_type([arguments/0]).
-type arguments() :: #{
    %% Set of exception filters specified by their ID. The set of all possible
    %% exception filters is defined by the `exceptionBreakpointFilters`
    %% capability. The `filter` and `filterOptions` sets are additive.
    filters := [binary()],

    %% Set of exception filters and their options. The set of all possible
    %% exception filters is defined by the `exceptionBreakpointFilters`
    %% capability. This attribute is only honored by a debug adapter if the
    %% corresponding capability `supportsExceptionFilterOptions` is true. The
    %% `filter` and `filterOptions` sets are additive.
    filterOptions => [exception_filter_options()],

    %% Configuration options for selected exceptions.
    %% The attribute is only honored by a debug adapter if the corresponding
    %% capability `supportsExceptionOptions` is true.
    exceptionOptions => [exception_options()]
}.
-type response() :: edb_dap_request_set_breakpoints:response().

-type exception_filter_options() :: #{
    %% ID of an exception filter returned by the `exceptionBreakpointFilters`
    %% capability.
    filterId := binary(),

    %% An expression for conditional exceptions.
    %% The exception breaks into the debugger if the result of the condition is
    %% true.
    condition => binary(),

    %% The mode of this exception breakpoint. If defined, this must be one of the
    %% `breakpointModes` the debug adapter advertised in its `Capabilities`.
    mode => binary()
}.

-type exception_options() :: #{
    %% A path that selects a single or multiple exceptions in a tree. If `path` is
    %% missing, the whole tree is selected.
    %% By convention the first segment of the path is a category that is used to
    %% group exceptions in the UI.
    path => [exception_path_segment()],

    %% Condition when a thrown exception should result in a break.
    breakMode := exception_break_mode()
}.

%% An ExceptionPathSegment represents a segment in a path that is used to
%% match leafs or nodes in a tree of exceptions.
%%
%% If a segment consists of more than one name, it matches the names provided
%% if negate is false or missing, or it matches anything except the names provided
%% if negate is true.
-type exception_path_segment() :: #{
    %% If false or missing this segment matches the names provided, otherwise it
    %% matches anything except the names provided.
    negate => boolean(),

    %% Depending on the value of `negate` the names that should match or not
    %% match.
    names := [binary()]
}.

-type exception_break_mode() ::
    % never breaks
    'never'
    % always breaks,
    | 'always'
    % breaks when exception unhandled
    | 'unhandled'
    % breaks if the exception is not handled by user code.
    | 'userUnhandled'.

-spec arguments_template() -> edb_dap_parse:template().
arguments_template() ->
    #{
        %% NB. We don't curretly support exception breakpoints,
        %% but they are part of the configuration protocol, so
        %% we expect to receive a message to with no filters
        %% as "configurationDone"
        filters => edb_dap_parse:empty_list(),
        filterOptions => {optional, edb_dap_parse:empty_list()},
        exceptionOptions => {optional, edb_dap_parse:empty_list()}
    }.

%% ------------------------------------------------------------------
%% Behaviour implementation
%% ------------------------------------------------------------------
-spec parse_arguments(edb_dap:arguments()) -> {ok, arguments()} | {error, Reason :: binary()}.
parse_arguments(Args) ->
    edb_dap_parse:parse(arguments_template(), Args, reject_unknown).

-spec handle(State, Args) -> edb_dap_request:reaction(response()) when
    State :: edb_dap_server:state(),
    Args :: arguments().
handle(State0 = #{state := configuring}, #{filters := []}) ->
    {ok, Subscription} = edb:subscribe(),
    {ok, resumed} = edb:continue(),
    #{
        new_state => State0#{
            state => attached,
            subscription => Subscription
        },
        response => edb_dap_request:success(#{breakpoints => []})
    };
handle(_UnexpectedState, _) ->
    edb_dap_request:unexpected_request().
