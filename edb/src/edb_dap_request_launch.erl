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

-export_type([arguments/0, run_in_terminal/0, config/0, target_node/0]).
-type arguments() :: #{
    runInTerminal := run_in_terminal(),
    config := config()
}.

-type run_in_terminal() :: edb_dap_reverse_request_run_in_terminal:arguments().
-type config() ::
    #{
        targetNode := target_node(),
        stripSourcePrefix => binary(),
        timeout => non_neg_integer()
    }.
-type target_node() :: #{
    name := node(),
    cookie := atom(),
    type => longnames | shortnames
}.

-spec arguments_template() -> edb_dap_parse:template().
arguments_template() ->
    #{
        runInTerminal => #{
            kind => {optional, edb_dap_parse:atoms([integrated, external])},
            title => {optional, edb_dap_parse:binary()},
            cwd => edb_dap_parse:binary(),
            args => edb_dap_parse:nonempty_list(edb_dap_parse:binary()),
            env =>
                {optional,
                    edb_dap_parse:map(
                        edb_dap_parse:binary(),
                        edb_dap_parse:choice([edb_dap_parse:null(), edb_dap_parse:binary()])
                    )},
            argsCanBeInterpretedByShell => {optional, edb_dap_parse:boolean()}
        },

        config =>
            #{
                targetNode => #{
                    name => edb_dap_parse:atom(),
                    cookie => edb_dap_parse:atom(),
                    type => {optional, edb_dap_parse:atoms([longnames, shortnames])}
                },
                stripSourcePrefix => {optional, edb_dap_parse:binary()},
                timeout => {optional, edb_dap_parse:non_neg_integer()}
            },

        %% TODO(T217166034) -- REMOVE ONCE VSCODE EXTENSIONS ARE UPDATED
        launchCommand =>
            {optional, #{
                cwd => {optional, edb_dap_parse:binary()},
                arguments => {optional, edb_dap_parse:list(edb_dap_parse:binary())}
            }}
    }.

%% ------------------------------------------------------------------
%% Behaviour implementation
%% ------------------------------------------------------------------
-spec parse_arguments(edb_dap:arguments()) -> {ok, config()} | {error, Reason :: binary()}.
parse_arguments(Args) ->
    Template = arguments_template(),
    edb_dap_parse:parse(Template, Args, allow_unknown).

-spec handle(State, Args) -> edb_dap_request:reaction() when
    State :: edb_dap_server:state(),
    Args :: arguments().
handle(
    State = #{state := initialized, client_info := ClientInfo = #{supportsRunInTerminalRequest := true}},
    Args = #{runInTerminal := RunInTerminal0}
) ->
    #{config := Config} = Args,

    WantsArgsCanBeInterpretedByShell = maps:get(argsCanBeInterpretedByShell, RunInTerminal0, false),
    SupportsArgsCanBeInterpretedByShell = maps:get(supportsArgsCanBeInterpretedByShell, ClientInfo, false),
    case {WantsArgsCanBeInterpretedByShell, SupportsArgsCanBeInterpretedByShell} of
        {true, false} ->
            edb_dap_request:abort(unsupported_by_client(~"argsCanBeInterpretedByShell", ClientInfo));
        _ ->
            ok
    end,
    %% TODO(T217166034) -- REMOVE ONCE VSCODE EXTENSIONS ARE UPDATED
    RunInTerminal1 =
        case Args of
            #{launchCommand := #{arguments := ExtraArgsComingFromVsCodeExtension}} ->
                #{args := Args0} = RunInTerminal0,
                Args1 = Args0 ++ ExtraArgsComingFromVsCodeExtension,
                RunInTerminal0#{args := Args1};
            _ ->
                RunInTerminal0
        end,
    RunInTerminal2 =
        case Args of
            #{launchCommand := #{cwd := CwdOverridenByVsCodeExtension}} ->
                RunInTerminal1#{cwd := CwdOverridenByVsCodeExtension};
            _ ->
                RunInTerminal1
        end,
    do_run_in_terminal(RunInTerminal2, Config, State);
handle(#{state := initialized, client_info := ClientInfo}, #{runInTerminal := _}) ->
    unsupported_by_client(~"runInTerminal", ClientInfo);
handle(_InvalidState, _Args) ->
    edb_dap_request:unexpected_request().

%% ------------------------------------------------------------------
%% Helpers
%% ------------------------------------------------------------------
-spec do_run_in_terminal(RunInTerminal, Config, State) -> edb_dap_request:reaction() when
    RunInTerminal :: run_in_terminal(),
    Config :: config(),
    State :: edb_dap_server:state().
do_run_in_terminal(RunInTerminal0, Config, State0 = #{state := initialized}) ->
    #{targetNode := #{name := Node, cookie := Cookie}} = Config,
    AttachTimeoutInSecs = maps:get(timeout, Config, ?DEFAULT_ATTACH_TIMEOUT_IN_SECS),
    StripSourcePrefix = maps:get(stripSourcePrefix, Config, ~""),

    RunInTerminal1 = update_erl_flags_env(RunInTerminal0),

    Cwd = maps:get(cwd, RunInTerminal1),
    RunInTerminalRequest = edb_dap_reverse_request_run_in_terminal:make_request(RunInTerminal1),

    State1 = State0#{
        state => launching,
        node => Node,
        cookie => Cookie,
        timeout => AttachTimeoutInSecs,
        cwd => edb_dap_utils:strip_suffix(Cwd, StripSourcePrefix)
    },
    #{
        response => edb_dap_request:success(),
        actions => [{reverse_request, RunInTerminalRequest}],
        new_state => State1
    }.

-spec update_erl_flags_env(RunInTerminal) -> RunInTerminal when RunInTerminal :: run_in_terminal().
update_erl_flags_env(RunInTerminal0 = #{env := Env = #{~"ERL_FLAGS" := ERL_FLAGS0}}) when is_binary(ERL_FLAGS0) ->
    ERL_FLAGS1 = <<ERL_FLAGS0/binary, ~" "/binary, ?ERL_FLAGS/binary>>,
    RunInTerminal0#{env => Env#{~"ERL_FLAGS" => ERL_FLAGS1}};
update_erl_flags_env(RunInTerminal0 = #{env := Env}) ->
    RunInTerminal0#{env => Env#{~"ERL_FLAGS" => ?ERL_FLAGS}};
update_erl_flags_env(RunInTerminal0) ->
    RunInTerminal0#{env => #{~"ERL_FLAGS" => ?ERL_FLAGS}}.

-spec unsupported_by_client(What, ClientInfo) -> edb_dap_request:error_reaction() when
    What :: binary(),
    ClientInfo :: edb_dap_server:client_info().
unsupported_by_client(What, ClientInfo) ->
    ClientName = maps:get(clientName, ClientInfo, "the client"),
    edb_dap_request:unsupported(io_lib:format("~s is not supported by ~s", [What, ClientName])).
