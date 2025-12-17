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
%% Code needed to initialize a debuggee node on attach.

-module(edb_bootstrap).

-oncall("whatsapp_server_devx").
-moduledoc false.
-compile(warn_missing_spec_all).

-export([bootstrap_debuggee/4]).

-record('__edb_bootstrap_failure__', {
    reason :: edb:bootstrap_failure()
}).

%% erlfmt:ignore-begin
% @fb-only[end= ]: -define(MODULES_USED_FOR_META_DEBUGGING, [waaat]).
-define(MODULES_USED_FOR_META_DEBUGGING, []). % @oss-only
%% erlfmt:ignore-end

-spec bootstrap_debuggee(Debugger, Subscribers, ReverseAttachCode, PauseAction) ->
    ok | {error, Reason}
when
    Debugger :: node(),
    Subscribers :: #{edb_events:subscription() => pid()},
    ReverseAttachCode :: none | binary(),
    PauseAction :: pause | keep_running,
    Reason :: edb:bootstrap_failure().
bootstrap_debuggee(Debugger, Subscribers, ReverseAttachCode, PauseAction) ->
    case is_edb_server_running() of
        true ->
            ok;
        false ->
            try
                check_vm_support(),
                inject_edb_modules(Debugger),
                start_edb_server(),
                subscribe_to_events(Subscribers),
                case PauseAction of
                    keep_running ->
                        ok;
                    pause ->
                        ok = edb_server:call(node(), {exclude_processes, [{proc, self()}]}),
                        ok = edb_server:call(node(), pause)
                end,
                prepare_environment_for_debugging_children_nodes(ReverseAttachCode)
            catch
                throw:Failure = #'__edb_bootstrap_failure__'{} ->
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
    erpc:call(Debugger, fun get_object_code__debugger_side/0).

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
%% Subscribe to events
%% --------------------------------------------------------------------
-spec subscribe_to_events(Subscribers) -> ok when
    Subscribers :: #{edb_events:subscription() => pid()}.
subscribe_to_events(Subscribers) ->
    edb_server:call(node(), {subscribe_to_events, Subscribers}).

%% --------------------------------------------------------------------
%% Environment preparation for debugging children nodes
%% --------------------------------------------------------------------
-spec prepare_environment_for_debugging_children_nodes(ReverseAttachCode) -> ok when
    ReverseAttachCode :: none | binary().
prepare_environment_for_debugging_children_nodes(none) ->
    ok;
prepare_environment_for_debugging_children_nodes(ReverseAttachCode) ->
    ReverseAttachCodeEscaped = escape_special_chars_for_erl_flags(ReverseAttachCode),
    NewFlags = lists:flatten(io_lib:format("-eval ~s", [ReverseAttachCodeEscaped])),
    CombinedFlags =
        % @fb-only[end= ]: % elp:ignore WA014 (no_os_getenv)
        case os:getenv("ERL_AFLAGS") of
            false ->
                NewFlags;
            Value ->
                % Only add NewFlags if ReverseAttachCode is not already present
                case string:find(Value, ReverseAttachCodeEscaped) of
                    nomatch -> NewFlags ++ " " ++ Value;
                    _ -> Value
                end
        end,
    true = os:putenv("ERL_AFLAGS", CombinedFlags),
    ok.

-spec escape_special_chars_for_erl_flags(CodeToInject :: binary()) -> iodata().
escape_special_chars_for_erl_flags(CodeToInject) ->
    % In ERL_FLAGS/ERL_AFLAGS, words are split by whitespace, subject to extra rules:
    %   - Things between single/double quotes are considered a single word (without the quotes)
    %   - The character that comes after a `\` is added verbatim to the current word.
    % So we use `\` to escape whitespace and quotes
    re:replace(CodeToInject, ~"[\s'\"]", ~"\\\\&", [global]).

%% --------------------------------------------------------------------
%% Error handling
%% --------------------------------------------------------------------
-spec bootstrap_failure(Reason) -> none() when
    Reason :: edb:bootstrap_failure().
bootstrap_failure(Reason) ->
    throw(#'__edb_bootstrap_failure__'{reason = Reason}).

-spec bootstrap_failure_reason(#'__edb_bootstrap_failure__'{}) -> Reason when
    Reason :: edb:bootstrap_failure().
bootstrap_failure_reason(#'__edb_bootstrap_failure__'{reason = Reason}) ->
    Reason.

%% --------------------------------------------------------------------
%% Code to be executed on the debugger node
%% --------------------------------------------------------------------
-spec get_object_code__debugger_side() -> [injectable_module()].
get_object_code__debugger_side() ->
    {ok, AllAppModules} = application:get_key(edb_core, modules),
    AppModulesToSkip = (debugger_only_modules())#{?MODULE => []},
    MetaDebuggingModules = [M || M <- ?MODULES_USED_FOR_META_DEBUGGING, {module, _} <- [code:ensure_loaded(M)]],
    [
        case code:get_object_code(Module) of
            Res = {_, _, _} -> Res
        end
     || Module <- AllAppModules ++ MetaDebuggingModules,
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
