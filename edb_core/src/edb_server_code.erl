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

-export([
    fetch_fun_block_surrounding/2
]).

-compile(warn_missing_spec_all).

%% erlfmt:ignore
% @fb-only

-type line() :: edb:line().

%% Defined in beam_lib but not exported
-type beam_lib_form() :: erl_parse:abstract_form() | erl_parse:form_info().
-type beam_lib_forms() :: [beam_lib_form()].

-spec fetch_fun_block_surrounding(module(), line()) -> {ok, [line()]} | {error, Error} when
    Error :: no_abstract_code | {beam_analysis, term()}.
fetch_fun_block_surrounding(Module, Line) ->
    case fetch_abstract_forms(Module) of
        {ok, Forms} ->
            case find_fun_block_surrounding(Line, Forms) of
                {ok, MinLine, MaxLine} ->
                    {ok, lists:seq(MinLine, MaxLine)};
                not_found ->
                    {error, {beam_analysis, {invalid_line, Module, Line}}}
            end;
        {error, Error} ->
            {error, Error}
    end.

-spec find_fun_block_surrounding(line(), beam_lib_forms()) -> {ok, line(), line()} | not_found.
find_fun_block_surrounding(_Line, []) ->
    not_found;
find_fun_block_surrounding(Line, [Form = {function, _Anno, _Name, _Arity, _Clauses}, NextForm | Forms]) ->
    NextFormLine = form_line(NextForm),
    case NextFormLine > Line of
        true ->
            %% Next form starts after Line, so we found the function
            case
                erl_parse:fold_anno(
                    fun(Anno, {MinLine, MaxLine}) ->
                        {min(erl_anno:line(Anno), MinLine), max(erl_anno:line(Anno), MaxLine)}
                    end,
                    {Line, Line},
                    Form
                )
            of
                %% fold_anno has a type that doesn't enforce accumulator type being preserved
                %% so we have to do this
                {MinLine, MaxLine} when is_integer(MinLine), is_integer(MaxLine) ->
                    {ok, MinLine, MaxLine}
            end;
        false ->
            find_fun_block_surrounding(Line, [NextForm | Forms])
    end;
find_fun_block_surrounding(Line, [_ | Forms]) ->
    %% Not a function form, so skip it
    find_fun_block_surrounding(Line, Forms).

-spec fetch_abstract_forms(module()) -> {ok, beam_lib_forms()} | {error, Error} when
    Error :: no_abstract_code | {beam_analysis, term()}.
fetch_abstract_forms(Module) ->
    case fetch_beam_filename(Module) of
        {error, Error} ->
            {error, {beam_analysis, Error}};
        {ok, ModuleBeamFile} ->
            case beam_lib:chunks(ModuleBeamFile, [abstract_code]) of
                {ok, {Module, [{abstract_code, {raw_abstract_v1, Forms}}]}} ->
                    {ok, Forms};
                {ok, {Module, [{abstract_code, no_abstract_code}]}} ->
                    {error, no_abstract_code};
                {ok, _} ->
                    %% This should never happen, but if it does, it's a bug in beam_lib
                    {error, {beam_analysis, unexpected}};
                {error, beam_lib, Error} ->
                    {error, {beam_analysis, {beam_lib, Error}}}
            end
    end.

-spec fetch_beam_filename(module()) -> {ok, file:filename()} | {error, Error} when
    Error :: non_existing | cover_compiled | preloaded | dynamically_compiled.
fetch_beam_filename(Module) ->
    case code:which(Module) of
        non_existing ->
            {error, non_existing};
        cover_compiled ->
            {error, cover_compiled};
        preloaded ->
            {error, preloaded};
        Filename ->
            case string:lowercase(filename:extension(Filename)) of
                ".beam" -> {ok, Filename};
                _ -> {error, dynamically_compiled}
            end
    end.

%% Functions to help manipulate line numbers within abstract forms

-spec form_line(beam_lib_form()) -> line().
form_line({eof, Location}) ->
    location_line(Location);
form_line({error, {Location, _, _}}) ->
    location_line(Location);
form_line({warning, {Location, _, _}}) ->
    location_line(Location);
form_line(Form) ->
    Anno = element(2, Form),
    erl_anno:line(Anno).

-spec location_line(erl_anno:location()) -> line().
location_line(Line) when is_integer(Line) -> Line;
location_line({Line, _Col}) -> Line.
