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

-module(edb_dap_request_disconnect).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-behaviour(edb_dap_request).

-export([parse_arguments/1, handle/2]).

-include_lib("kernel/include/logger.hrl").

%% ------------------------------------------------------------------
%% Types
%% ------------------------------------------------------------------
%%% https://microsoft.github.io/debug-adapter-protocol/specification#Requests_Disconnect
-type arguments() :: #{
    %  A value of true indicates that this `disconnect` request is part of a
    % restart sequence
    restart => boolean(),

    % Indicates whether the debuggee should be terminated when the debugger is
    % disconnected.
    % If unspecified, the debug adapter is free to do whatever it thinks is best.
    % The attribute is only honored by a debug adapter if the corresponding
    % capability `supportTerminateDebuggee` is true.
    terminateDebuggee => boolean(),

    % Indicates whether the debuggee should stay suspended when the debugger is
    % disconnected.
    % If unspecified, the debuggee should resume execution.
    % The attribute is only honored by a debug adapter if the corresponding
    % capability `supportSuspendDebuggee` is true.
    suspendDebuggee => boolean()
}.

-export_type([arguments/0]).

-spec arguments_template() -> edb_dap_parse:template().
arguments_template() ->
    #{
        restart => {optional, edb_dap_parse:boolean()},
        terminateDebuggee => {optional, edb_dap_parse:boolean()},
        suspendDebuggee => {optional, edb_dap_parse:boolean()}
    }.

%% ------------------------------------------------------------------
%% Behaviour implementation
%% ------------------------------------------------------------------
-spec parse_arguments(edb_dap:arguments()) -> {ok, arguments()} | {error, Reason :: binary()}.
parse_arguments(Args) ->
    Template = arguments_template(),
    edb_dap_parse:parse(Template, Args, allow_unknown).

-spec handle(State, Args) -> edb_dap_request:reaction() when
    State :: edb_dap_server:state(),
    Args :: arguments().
handle(State, Args) ->
    ok = edb:terminate(),

    case shouldTerminateDebuggee(State, Args) of
        true ->
            Victims = get_victims(State),
            kill_victims(Victims);
        false ->
            ok
    end,

    #{
        response => edb_dap_request:success(),
        actions => [terminate]
    }.

%% ------------------------------------------------------------------
%% Helpers
%% ------------------------------------------------------------------

-type victims() ::
    none
    | #{
        node := node(),
        process_id := number(),
        shell_process_id => number()
    }.

-spec shouldTerminateDebuggee(State, Args) -> boolean() when
    State :: edb_dap_server:state(),
    Args :: arguments().
shouldTerminateDebuggee(_State, #{terminateDebuggee := ShouldTerminateIt}) ->
    ShouldTerminateIt;
shouldTerminateDebuggee(#{type := #{request := launch}}, _Args) ->
    true;
shouldTerminateDebuggee(_, _) ->
    false.

-spec get_victims(State) -> Victims when
    State :: edb_dap_server:state(),
    Victims :: victims().
get_victims(#{node := Node, type := AttachType}) ->
    Victims0 = maps:with([process_id, shell_process_id], AttachType),
    Victims1 = Victims0#{node => Node},
    Victims1;
get_victims(_State) ->
    none.

-spec kill_victims(Victims) -> ok when
    Victims :: victims().
kill_victims(none) ->
    ok;
kill_victims(Victims = #{node := Node, process_id := ProcessId}) ->
    KillReqTimeout = 5,
    case try_async(fun() -> kill_node(Node) end, KillReqTimeout * 1_000) of
        ok ->
            ok;
        timeout ->
            ?LOG_WARNING("erlang:halt() on debuggee timed out after ~p secs", [KillReqTimeout]),
            try_async(fun() -> kill_os_process(ProcessId, force) end, 1_000)
    end,

    case Victims of
        #{shell_process_id := ShellProcessId} ->
            case try_async(fun() -> kill_os_process(ShellProcessId, dont_force) end, KillReqTimeout * 1_000) of
                ok ->
                    ok;
                timeout ->
                    ?LOG_WARNING("Killing shell process ~p timed-out after ~p secs", [ShellProcessId, KillReqTimeout])
            end,
            try_async(fun() -> kill_os_process(ShellProcessId, force) end, 1_000);
        #{} ->
            ok
    end,
    ok.

-spec try_async(Fun, Timeout) -> ok | timeout when
    Fun :: fun(() -> ok),
    Timeout :: timeout().
try_async(Fun, Timeout) ->
    Ref = erlang:make_ref(),
    Me = self(),
    erlang:spawn(fun() ->
        Fun(),
        Me ! Ref
    end),
    receive
        Ref -> ok
    after Timeout -> timeout
    end.

-spec kill_node(Node) -> ok when Node :: node().
kill_node(Node) ->
    % elp:ignore W0014 -- debugger relies on dist
    catch erpc:call(Node, erlang, halt, [0]),
    ok.

-spec kill_os_process(ProcessId, force | dont_force) -> ok when
    ProcessId :: number().
kill_os_process(ProcessId, ForceOrNot) ->
    case os:type() of
        {unix, _} -> kill_unix_process(ProcessId, ForceOrNot);
        {win32, _} -> kill_win_process(ProcessId, ForceOrNot)
    end.

-spec kill_unix_process(ProcessId, ForceOrNot) -> ok when
    ProcessId :: number(),
    ForceOrNot :: force | dont_force.
kill_unix_process(ProcessId, force) ->
    os:cmd("kill -9 " ++ integer_to_list(ProcessId)),
    ok;
kill_unix_process(ProcessId, dont_force) ->
    os:cmd("kill " ++ integer_to_list(ProcessId)),
    ok.

-spec kill_win_process(ProcessId, ForceOrNot) -> ok when
    ProcessId :: number(),
    ForceOrNot :: force | dont_force.
kill_win_process(ProcessId, force) ->
    os:cmd("taskkill /F /PID " ++ integer_to_list(ProcessId)),
    ok;
kill_win_process(ProcessId, dont_force) ->
    os:cmd("taskkill /PID " ++ integer_to_list(ProcessId)),
    ok.
