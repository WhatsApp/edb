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
% @fb-only
-compile(warn_missing_spec_all).

-moduledoc false.

-export([eval/4]).

-spec eval(F, X, SourceNode, Timeout) ->
    {ok, Result} | {eval_error, edb:eval_error()} | {failed_to_load_module, module(), term()}
when
    F :: fun((X) -> Result),
    SourceNode :: node(),
    Timeout :: timeout().
eval(F, X, SourceNode, Timeout) ->
    {Mod, _, _} = erlang:fun_info_mfa(F),
    case load_module_if_necessary(Mod, SourceNode) of
        {error, LoadFailureReason} ->
            {failed_to_load_module, Mod, LoadFailureReason};
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

% ---------------------------------------------------------------------------
% Helpers
% ---------------------------------------------------------------------------

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
            try erpc:call(SourceNode, code, get_object_code, [Module]) of
                error ->
                    {error, not_found};
                {Module, BeamBinary, BeamFileName} ->
                    case code:load_binary(Module, BeamFileName, BeamBinary) of
                        {module, Module} -> ok;
                        Error = {error, _} -> Error
                    end
            catch
                Class:Reason -> {error, {rpc_error, {Class, Reason}}}
            end
    end.
