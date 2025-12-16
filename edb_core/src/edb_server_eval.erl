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
-module(edb_server_eval).

%% erlfmt:ignore
% @fb-only: -oncall("whatsapp_server_devx").
-compile(warn_missing_spec_all).

-moduledoc false.

-export([eval/5]).
-export([stash_object_code/3, get_object_code/1]).

% ---------------------------------------------------------------------------
% Public functions
% ---------------------------------------------------------------------------

-spec eval(F, X, SourceNode, Timeout, Deps) ->
    {ok, Result} | {eval_error, edb:eval_error()} | {failed_to_load_module, module(), term()}
when
    F :: fun((X) -> Result),
    SourceNode :: node(),
    Timeout :: timeout(),
    Deps :: [module()].
eval(F, X, SourceNode, Timeout, Deps) ->
    {Mod, _, _} = erlang:fun_info_mfa(F),
    case load_modules_if_necessary([Mod | Deps], SourceNode) of
        {error, FailedMod, LoadFailureReason} ->
            {failed_to_load_module, FailedMod, LoadFailureReason};
        ok ->
            ResultRef = erlang:make_ref(),
            Parent = self(),
            {Pid, MonitorRef} = erlang:spawn_monitor(fun() ->
                try F(X) of
                    Result -> Parent ! {ResultRef, {ok, Result}}
                catch
                    Class:Reason:ST ->
                        Exc = {exception, #{class => Class, reason => Reason, stacktrace => ST}},
                        Parent ! {ResultRef, Exc}
                end
            end),
            {Final, PurgeNeeded} =
                receive
                    {ResultRef, Result = {ok, _}} ->
                        {Result, true};
                    {ResultRef, Exc = {exception, _}} ->
                        {{eval_error, Exc}, true};
                    {'DOWNER', MonitorRef, process, Pid, ExitReason} ->
                        {{eval_error, {killed, ExitReason}}, false}
                after Timeout ->
                    erlang:exit(Pid, {timeout, MonitorRef}),
                    receive
                        {'DOWN', MonitorRef, process, Pid, ExitReason} ->
                            case ExitReason of
                                {timeout, MonitorRef} ->
                                    {{eval_error, timeout}, false};
                                _ ->
                                    {{eval_error, {killed, ExitReason}}, false}
                            end;
                        {ResultRef, Result = {ok, _}} ->
                            {Result, true};
                        {ResultRef, Exc = {exception, _}} ->
                            {{eval_error, Exc}, true}
                    end
                end,
            case PurgeNeeded of
                false ->
                    ok;
                true ->
                    receive
                        {'DOWN', MonitorRef, process, Pid, _} -> ok
                    end
            end,
            Final
    end.

-spec stash_object_code(Module, BeamFilename, Code) -> ok when
    Module :: module(),
    BeamFilename :: file:filename(),
    Code :: binary().
stash_object_code(Module, BeamFilename, Code) ->
    persistent_term:put(stash_key(Module), {ok, BeamFilename, Code}).

-spec get_object_code(Module) -> {ok, BeamFilename, Code} | not_found when
    Module :: module(),
    BeamFilename :: file:filename(),
    Code :: binary().
get_object_code(Module) ->
    case persistent_term:get(stash_key(Module), not_found) of
        Stashed = {ok, _, _} ->
            Stashed;
        not_found ->
            case code:get_object_code(Module) of
                error -> not_found;
                {Module, Code, BeamFilename} -> {ok, BeamFilename, Code}
            end
    end.

% ---------------------------------------------------------------------------
% Helpers
% ---------------------------------------------------------------------------

-spec load_modules_if_necessary(Modules, SourceNode) -> ok | {error, BadModule, Reason} when
    Modules :: [module()],
    BadModule :: module(),
    SourceNode :: node(),
    Reason :: not_found | badarg | code:load_error_rsn() | {rpc_error, term()}.
load_modules_if_necessary(Modules, SourceNode) ->
    lists:foldl(
        fun
            (Module, ok) ->
                case load_module_if_necessary(Module, SourceNode) of
                    ok -> ok;
                    {error, Reason} -> {error, Module, Reason}
                end;
            (_, Error) ->
                Error
        end,
        ok,
        Modules
    ).

-spec load_module_if_necessary(Module, SourceNode) -> ok | {error, Reason} when
    Module :: module(),
    SourceNode :: node(),
    Reason :: not_found | badarg | code:load_error_rsn() | {rpc_error, term()}.
load_module_if_necessary(Module, SourceNode) ->
    case code:is_loaded(Module) of
        {file, _} ->
            ok;
        false ->
            % elp:ignore W0014 (cross_node_eval) -- allowed on debugger
            try erpc:call(SourceNode, ?MODULE, get_object_code, [Module]) of
                not_found ->
                    {error, not_found};
                {ok, BeamFilename, BeamBinary} ->
                    case code:load_binary(Module, BeamFilename, BeamBinary) of
                        {module, Module} -> ok;
                        Error = {error, _} -> Error
                    end
            catch
                Class:Reason -> {error, {rpc_error, {Class, Reason}}}
            end
    end.

-spec stash_key(Module) -> term() when
    Module :: module().
stash_key(Module) ->
    {?MODULE, Module}.
