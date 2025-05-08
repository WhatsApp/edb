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

-module(edb_server_code).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-export([get_debug_info/2]).
-export([module_source/1]).

% erlint-ignore dialyzer_override
-dialyzer({nowarn_function, [get_debug_info/2]}).
-ignore_xref([{code, get_debug_info, 1}]).

%% --------------------------------------------------------------------
%% Types
%% --------------------------------------------------------------------

-export_type([var_debug_info/0]).

-type var_name() :: binary().

-type var_debug_info() ::
    {x, non_neg_integer()} | {y, non_neg_integer()} | {value, term()}.

-export_type([call_target/0]).
-type call_target() ::
    % remote function
    {M :: module() | var_name(), F :: atom() | var_name(), A :: non_neg_integer()}
    % local function
    | {F :: atom() | var_name(), A :: non_neg_integer()}
    % function reference
    | var_name().

%% --------------------------------------------------------------------
%% Debug info
%% --------------------------------------------------------------------

-spec get_debug_info(Module, Line) -> {ok, Result} | {error, Reason} when
    Module :: module(),
    Line :: pos_integer(),
    Reason :: not_found | no_debug_info | line_not_found,
    Result :: #{
        vars := #{var_name() => var_debug_info()},
        calls := [call_target()]
    }.
get_debug_info(Module, Line) when is_atom(Module) ->
    try
        % elp:ignore W0017 function available only on patched version of OTP
        code:get_debug_info(Module)
    of
        none ->
            {error, no_debug_info};
        DebugInfo when is_list(DebugInfo) ->
            case lists:keyfind(Line, 1, DebugInfo) of
                false ->
                    {error, line_not_found};
                {Line, LineDebugInfo} ->
                    Vars =
                        #{
                            Var => assert_is_var_debug_info(Val)
                         || {Var, Val} <- maps:get(vars, LineDebugInfo, []), is_binary(Var)
                        },
                    Calls = maps:get(calls, LineDebugInfo, []),
                    {ok, #{vars => Vars, calls => Calls}}
            end
    catch
        _:badarg ->
            {error, not_found}
    end.

-spec assert_is_var_debug_info(term()) -> var_debug_info().
assert_is_var_debug_info(X = {x, N}) when is_integer(N) -> X;
assert_is_var_debug_info(Y = {y, N}) when is_integer(N) -> Y;
assert_is_var_debug_info(V = {value, _}) -> V.

% --------------------------------------------------------------------
% module_source: Source location of a module
% --------------------------------------------------------------------

-spec module_source(Module :: module()) -> undefined | file:filename().
module_source(Module) ->
    try Module:module_info(compile) of
        CompileInfo when is_list(CompileInfo) ->
            case proplists:get_value(source, CompileInfo, undefined) of
                undefined ->
                    guess_module_source(Module);
                SourcePath ->
                    case filename:pathtype(SourcePath) of
                        relative ->
                            SourcePath;
                        _ ->
                            case filelib:is_regular(SourcePath) of
                                true ->
                                    SourcePath;
                                false ->
                                    case guess_module_source(Module) of
                                        undefined ->
                                            % We did our best, but this is the best we have
                                            SourcePath;
                                        GuessedSourcePath ->
                                            GuessedSourcePath
                                    end
                            end
                    end
            end
    catch
        _:_ ->
            undefined
    end.

-spec guess_module_source(Module :: module()) -> undefined | file:filename().
guess_module_source(Module) ->
    BeamName = atom_to_list(Module) ++ ".beam",
    case edb_server_call_proc:code_where_is_file(BeamName) of
        {call_error, _} ->
            undefined;
        {call_ok, non_existing} ->
            undefined;
        {call_ok, BeamPath} ->
            case filelib:find_source(BeamPath) of
                {ok, SourcePath} when is_list(SourcePath) ->
                    % eqwalizer:ignore incompatible_types -- file:name() vs file:filename() hell
                    SourcePath;
                _ ->
                    undefined
            end
    end.
