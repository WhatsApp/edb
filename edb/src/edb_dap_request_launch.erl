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
    name := binary(),
    cookie => binary(),
    type => binary()
}.

-spec arguments_template() -> edb_dap_parse:template().
arguments_template() ->
    #{
        launchCommand => #{
            cwd => fun is_binary/1,
            command => fun is_binary/1,
            arguments => {optional, fun is_valid_arguments/1},
            env => {optional, fun is_valid_env/1}
        },
        targetNode => #{
            name => fun is_binary/1,
            cookie => {optional, fun is_binary/1},
            type => {optional, fun is_node_type/1}
        },
        stripSourcePrefix => {optional, fun is_binary/1},
        timeout => {optional, fun edb_dap_parse:is_non_neg_integer/1}
    }.

%% ------------------------------------------------------------------
%% Behaviour implementation
%% ------------------------------------------------------------------
-spec parse_arguments(edb_dap:arguments()) -> {ok, arguments()} | {error, Reason :: binary()}.
parse_arguments(Args) ->
    parse(Args).

-spec handle(State, Args) -> edb_dap_request:reaction() when
    State :: edb_dap_state:t(),
    Args :: arguments().
handle(State, Args) ->
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
    #{
        response => #{success => true},
        actions => [{reverse_request, RunInTerminalRequest}],
        state => edb_dap_state:set_context(State, context(TargetNode, AttachTimeoutInSecs, Cwd, StripSourcePrefix))
    }.

%% ------------------------------------------------------------------
%% Helpers
%% ------------------------------------------------------------------
-spec context(TargetNode, AttachTimeout, Cwd, StripSourcePrefix) -> edb_dap_state:context() when
    TargetNode :: target_node(),
    AttachTimeout :: non_neg_integer(),
    Cwd :: binary(),
    StripSourcePrefix :: binary().
context(TargetNode, AttachTimeout, Cwd, StripSourcePrefix) ->
    #{
        target_node => edb_dap_state:make_target_node(TargetNode),
        attach_timeout => AttachTimeout,
        cwd => Cwd,
        strip_source_prefix => StripSourcePrefix,
        cwd_no_source_prefix => edb_dap_utils:strip_suffix(Cwd, StripSourcePrefix)
    }.

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

-spec is_valid_arguments(term()) -> boolean().
is_valid_arguments(Arguments) when is_list(Arguments) ->
    lists:all(fun is_binary/1, Arguments);
is_valid_arguments(_) ->
    false.

-spec is_node_type(term()) -> boolean().
is_node_type(Type) when is_binary(Type) ->
    lists:member(Type, [~"longnames", ~"shortnames"]);
is_node_type(_Type) ->
    false.

-spec is_valid_env(term()) -> boolean().
is_valid_env(Env) when is_map(Env) ->
    lists:all(fun edb_dap_parse:is_true/1, [is_atom(Key) andalso is_binary(Value) || Key := Value <- Env]);
is_valid_env(_) ->
    false.
