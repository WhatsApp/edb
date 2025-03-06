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

-module(edb_dap_reverse_request_run_in_terminal).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-behaviour(edb_dap_reverse_request).

-export([make_request/1, handle_response/2]).

-include("edb_dap.hrl").

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------
%%% https://microsoft.github.io/debug-adapter-protocol/specification#Reverse_Requests_RunInTerminal
-type arguments() :: #{
    %%  What kind of terminal to launch. Defaults to `integrated` if not specified.
    %% Values: 'integrated', 'external'
    kind => binary(),

    %% Title of the terminal.
    title => binary(),

    %% Working directory for the command. For non-empty, valid paths this
    %% typically results in execution of a change directory command.
    cwd => binary(),

    %% List of arguments. The first argument is the command to run.
    args := [binary()],

    %% Environment key-value pairs that are added to or removed from the default
    %% environment.
    env => #{binary() => binary()},

    %% This property should only be set if the corresponding capability
    %% `supportsArgsCanBeInterpretedByShell` is true. If the client uses an
    %% intermediary shell to launch the application, then the client must not
    %% attempt to escape characters with special meanings for the shell. The user
    %% is fully responsible for escaping as needed and that arguments using
    %% special characters may not be portable across shells.
    argsCanBeInterpretedByShell => boolean()
}.

-type response_body() :: #{
    %% The process ID. The value should be less than or equal to 2147483647 * (2^31-1).
    %% NB. Currently not sent by VS Code. See https://github.com/microsoft/vscode/issues/61640#issuecomment-432696354
    processId => number(),

    %% The process ID of the terminal shell. The value should be less than or
    %% equal to 2147483647 (2^31-1).
    shellProcessId => number()
}.

-export_type([arguments/0, response_body/0]).

%% ------------------------------------------------------------------
%% Behaviour implementation
%% ------------------------------------------------------------------
-spec make_request(Args) -> edb_dap_reverse_request:request(Args) when
    Args :: arguments().
make_request(Args) ->
    #{command => ~"runInTerminal", arguments => Args}.

-spec handle_response(edb_dap_server:state(), response_body()) -> edb_dap_reverse_request:reaction().
handle_response(State0 = #{state := launching, node := Node, cookie := Cookie, timeout := TimeoutInSecs}, _Body) ->
    case edb:attach(#{node => Node, timeout => TimeoutInSecs * 1000, cookie => Cookie}) of
        ok ->
            ok = edb:pause(),
            State1 = maps:without([cookie, timeout], State0),
            State2 = State1#{state => configuring},
            #{actions => [{event, edb_dap_event:initialized()}], new_state => State2};
        {error, Reason} ->
            #{
                new_state => #{state => terminating},
                actions => [{event, edb_dap_event:terminated()}],
                error =>
                    {user_error, ?ERROR_TIMED_OUT, io_lib:format("Attaching to node: ~p failed: ~p", [Node, Reason])}
            }
    end;
handle_response(_UnexpectedState, _) ->
    edb_dap_reverse_request:unexpected_response().
