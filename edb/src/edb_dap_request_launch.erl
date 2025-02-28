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

-module(edb_dap_request_launch).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-behaviour(edb_dap_request).

-export([parse_arguments/1, handle/2]).

-define(DEFAULT_ATTACH_TIMEOUT_IN_SECS, 60).
-define(ERL_FLAGS, ~"+D").

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------
%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_Launch
%%% Notice that, since launching is debugger/runtime specific, the arguments for this request are
%%% not part of the DAP specification itself.

-export_type([arguments/0, target_node/0]).
-type arguments() :: #{
    launchCommand := #{
        cwd := binary(),
        command := binary(),
        arguments => [binary()],
        env => #{binary() => binary()}
    },
    targetNode := target_node(),
    stripSourcePath => binary()
}.
-type target_node() :: #{
    name := node(),
    cookie => atom(),
    type => longnames | shortnames
}.

-spec arguments_template() -> edb_dap_parse:template().
arguments_template() ->
    #{
        launchCommand => #{
            cwd => edb_dap_parse:binary(),
            command => edb_dap_parse:binary(),
            arguments => {optional, edb_dap_parse:list(edb_dap_parse:binary())},
            env => {optional, edb_dap_parse:map(edb_dap_parse:binary(), edb_dap_parse:binary())}
        },
        targetNode => #{
            name => edb_dap_parse:atom(),
            cookie => {optional, edb_dap_parse:atom()},
            type => {optional, edb_dap_parse:atoms([longnames, shortnames])}
        },
        stripSourcePrefix => {optional, edb_dap_parse:binary()},
        timeout => {optional, edb_dap_parse:non_neg_integer()}
    }.

%% ------------------------------------------------------------------
%% Behaviour implementation
%% ------------------------------------------------------------------
-spec parse_arguments(edb_dap:arguments()) -> {ok, arguments()} | {error, Reason :: binary()}.
parse_arguments(Args) ->
    parse(Args).

-spec handle(State, Args) -> edb_dap_request:reaction() when
    State :: edb_dap_server:state(),
    Args :: arguments().
handle(State0 = #{state := initialized}, Args) ->
    #{launchCommand := LaunchCommand, targetNode := TargetNode} = Args,
    #{cwd := Cwd, command := Command} = LaunchCommand,
    AttachTimeoutInSecs = maps:get(timeout, Args, ?DEFAULT_ATTACH_TIMEOUT_IN_SECS),
    StripSourcePrefix = maps:get(stripSourcePrefix, Args, <<>>),
    Arguments = maps:get(arguments, LaunchCommand, []),
    Env = maps:get(env, LaunchCommand, #{}),
    RunInTerminalRequest = edb_dap_reverse_request_run_in_terminal:make_request(#{
        kind => ~"integrated",
        title => ~"EDB",
        cwd => Cwd,
        args => [Command | Arguments],
        env => Env#{~"ERL_FLAGS" => ?ERL_FLAGS}
    }),
    State1 = State0#{
        state => launching,
        context => #{
            target_node => TargetNode,
            attach_timeout => AttachTimeoutInSecs,
            cwd => Cwd,
            strip_source_prefix => StripSourcePrefix,
            cwd_no_source_prefix => edb_dap_utils:strip_suffix(Cwd, StripSourcePrefix)
        }
    },
    #{
        response => #{success => true},
        actions => [{reverse_request, RunInTerminalRequest}],
        state => State1
    };
handle(_InvalidState, _Args) ->
    edb_dap_request:unexpected_request().

%% ------------------------------------------------------------------
%% Helpers
%% ------------------------------------------------------------------

-spec parse(term()) -> {ok, arguments()} | {error, HumarReadableReason :: binary()}.
parse(RobustConfig = #{config := _}) ->
    Template = #{config => arguments_template()},
    Filtered = maps:with([config], RobustConfig),
    case edb_dap_parse:parse(Template, Filtered, reject_unknown) of
        {ok, #{config := Parsed}} -> {ok, Parsed};
        Error = {error, _} -> Error
    end;
parse(FlatConfig) ->
    Template = arguments_template(),
    edb_dap_parse:parse(Template, FlatConfig, allow_unknown).
