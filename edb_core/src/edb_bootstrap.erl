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
%% % @format
%%
%% @doc Code needed to initialize a debuggee node on attach.

-module(edb_bootstrap).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-export([bootstrap_debuggee/2]).

-define(BOOTSTRAP_FAILURE_MARKER, '__edb_bootstrap_failure__').

-spec bootstrap_debuggee(Debugger, PauseAction) -> ok | {error, Reason} when
    Debugger :: node(),
    PauseAction :: pause | keep_running,
    Reason :: edb:bootstrap_failure().
bootstrap_debuggee(Debugger, PauseAction) ->
    case is_edb_server_running() of
        true ->
            ok;
        false ->
            try
                check_vm_support(),
                inject_edb_modules(Debugger),
                start_edb_server(),
                case PauseAction of
                    keep_running ->
                        ok;
                    pause ->
                        ok = edb_server:call(node(), {exclude_processes, [{proc, self()}]}),
                        ok = edb_server:call(node(), pause)
                end
            catch
                throw:Failure = {?BOOTSTRAP_FAILURE_MARKER, _} ->
                    {error, bootstrap_failure_reason(Failure)}
            end
    end.

-spec check_vm_support() -> ok.
check_vm_support() ->
    try erl_debugger:supported() of
        true ->
            ok;
        false ->
            bootstrap_failure({no_debugger_support, not_enabled})
    catch
        error:undef ->
            bootstrap_failure({no_debugger_support, {missing, erl_debugger}})
    end.

%% --------------------------------------------------------------------
%% Code injection
%% --------------------------------------------------------------------
-type injectable_module() :: {module(), binary(), file:filename()}.

-spec inject_edb_modules(Debugger) -> ok when
    Debugger :: node().
inject_edb_modules(Debugger) ->
    case Debugger =:= node() of
        true ->
            % edb already present locally
            ok;
        false ->
            Modules = get_object_code(Debugger),
            [ok = load_module(Module, Binary, Filename) || {Module, Binary, Filename} <- Modules]
    end,
    ok.

-spec get_object_code(Debugger) -> [injectable_module()] when
    Debugger :: module().
get_object_code(Debugger) ->
    % elp:ignore W0014 -- debugger relies on dist
    Modules = erpc:call(Debugger, fun get_object_code__debugger_side/0),
    % eqwalizer:fixme -- erpc:call() ought to return the type of the callee
    Modules.

-spec load_module(Module, Binary, Filename) -> ok when
    Module :: module(), Binary :: binary(), Filename :: file:filename().
load_module(Module, Binary, Filename) ->
    case code:load_binary(Module, Filename, Binary) of
        {module, Module} -> ok;
        {error, Reason} -> bootstrap_failure({module_injection_failed, Module, Reason})
    end.

%% --------------------------------------------------------------------
%% edb_server initialization
%% --------------------------------------------------------------------
-spec is_edb_server_running() -> boolean().
is_edb_server_running() ->
    try edb_server:find() of
        undefined -> false;
        Pid when is_pid(Pid) -> true
    catch
        error:undef ->
            % edb_server module not even there
            false
    end.

-spec start_edb_server() -> ok.
start_edb_server() ->
    case edb_server:start() of
        ok ->
            ok;
        {error, failed_to_register} ->
            % Likely started concurrently
            ok;
        {error, unsupported} ->
            bootstrap_failure({no_debugger_support, not_enabled})
    end.

%% --------------------------------------------------------------------
%% Error handling
%% --------------------------------------------------------------------
-spec bootstrap_failure(Reason) -> none() when
    Reason :: edb:bootstrap_failure().
bootstrap_failure(Reason) ->
    throw({?BOOTSTRAP_FAILURE_MARKER, Reason}).

-spec bootstrap_failure_reason({?BOOTSTRAP_FAILURE_MARKER, term()}) -> Reason when
    Reason :: edb:bootstrap_failure().
bootstrap_failure_reason({?BOOTSTRAP_FAILURE_MARKER, Reason}) ->
    % eqwalizer:ignore -- term will only be produced using bootstrap_failure/0
    Reason.

%% --------------------------------------------------------------------
%% Code to be executed on the debugger node
%% --------------------------------------------------------------------
-spec get_object_code__debugger_side() -> [injectable_module()].
get_object_code__debugger_side() ->
    {ok, AllAppModules} = application:get_key(edb_core, modules),
    AppModulesToSkip = (debugger_only_modules())#{?MODULE => []},
    [
        case code:get_object_code(Module) of
            Res = {_, _, _} -> Res
        end
     || Module <- AllAppModules,
        not maps:is_key(Module, AppModulesToSkip)
    ].

-spec debugger_only_modules() -> #{module() => binary()}.
debugger_only_modules() ->
    Modules = [
        edb,
        edb_core_app,
        edb_core_sup,
        edb_gatekeeper,
        edb_node_monitor
    ],
    % Sanity-check: if the module exists, getting the md5 succeeds
    #{Mod => Mod:module_info(md5) || Mod <- Modules}.
