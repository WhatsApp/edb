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

-module(edb_boot).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-export([debuggee_boot/1]).

-define(BOOT_FAILURE_MARKER, '__edb_boot_failure__').

-spec debuggee_boot(Debugger) -> ok | {error, Reason} when
    Debugger :: node(),
    Reason :: edb:boot_failure().
debuggee_boot(Debugger) ->
    case is_edb_server_running() of
        true ->
            ok;
        false ->
            try
                check_vm_support(),
                inject_edb_modules(Debugger),
                start_edb_server(),
                ok
            catch
                throw:Failure = {?BOOT_FAILURE_MARKER, _} ->
                    {error, boot_failure_reason(Failure)}
            end
    end.

-spec check_vm_support() -> ok.
check_vm_support() ->
    try erl_debugger:supported() of
        true ->
            ok;
        false ->
            boot_failure({no_debugger_support, not_enabled})
    catch
        error:undef ->
            boot_failure({no_debugger_support, {missing, erl_debugger}})
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
        {error, Reason} -> boot_failure({module_injection_failed, Module, Reason})
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
            boot_failure({no_debugger_support, not_enabled})
    end.

%% --------------------------------------------------------------------
%% Error handling
%% --------------------------------------------------------------------
-spec boot_failure(Reason) -> none() when
    Reason :: edb:boot_failure().
boot_failure(Reason) ->
    throw({?BOOT_FAILURE_MARKER, Reason}).

-spec boot_failure_reason({?BOOT_FAILURE_MARKER, term()}) -> Reason when
    Reason :: edb:boot_failure().
boot_failure_reason({?BOOT_FAILURE_MARKER, Reason}) ->
    % eqwalizer:ignore -- term will only be produced using boot_failure/0
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
        edb_node_monitor
    ],
    % Sanity-check: if the module exists, getting the md5 succeeds
    #{Mod => Mod:module_info(md5) || Mod <- Modules}.
