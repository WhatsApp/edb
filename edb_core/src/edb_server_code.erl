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

-export([fetch_abstract_forms/1]).
-export([fetch_fun_block_surrounding/2]).
-export([get_call_target/2]).
-export([module_source/1]).

-compile(warn_missing_spec_all).

%% erlfmt:ignore
% @fb-only

%% --------------------------------------------------------------------
%% Types
%% --------------------------------------------------------------------

-type line() :: edb:line().

%% Defined in beam_lib but not exported
-export_type([form/0, forms/0]).
-type form() :: erl_parse:abstract_form() | erl_parse:form_info().
-type forms() :: [form()].

%% --------------------------------------------------------------------
%% fetch_abstract_forms: fetch abstract forms from beam file
%% --------------------------------------------------------------------

-spec fetch_abstract_forms(Module) -> {ok, forms()} | {error, Error} when
    Module :: module(),
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

-spec fetch_beam_filename(Module) -> {ok, file:filename()} | {error, Error} when
    Module :: module(),
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

%% --------------------------------------------------------------------
%% fetch_fun_block_surrounding: finding lines of functions
%% --------------------------------------------------------------------

-spec fetch_fun_block_surrounding(Line, Forms) -> {ok, [line()]} | {error, Error} when
    Line :: line(),
    Forms :: forms(),
    Error :: {beam_analysis, {invalid_line, Line}}.
fetch_fun_block_surrounding(Line, Forms) ->
    case find_fun_block_surrounding(Line, Forms) of
        {ok, MinLine, MaxLine} ->
            {ok, lists:seq(MinLine, MaxLine)};
        not_found ->
            {error, {beam_analysis, {invalid_line, Line}}}
    end.

-spec find_fun_block_surrounding(Line, Forms) -> {ok, line(), line()} | not_found when
    Line :: line(),
    Forms :: forms().
find_fun_block_surrounding(Line, Forms) ->
    case find_fun_containing_line(Line, Forms) of
        not_found ->
            not_found;
        {ok, Form} ->
            case
                erl_parse:fold_anno(
                    fun(Anno, {MinLine, MaxLine}) ->
                        case erl_anno:line(Anno) of
                            0 ->
                                % Line information is somehow missing on this ast node, ignore
                                {MinLine, MaxLine};
                            AnnoLine ->
                                {min(AnnoLine, MinLine), max(AnnoLine, MaxLine)}
                        end
                    end,
                    {Line, Line},
                    Form
                )
            of
                %% fold_anno has a type that doesn't enforce accumulator type being preserved
                %% so we have to do this
                {MinLine, MaxLine} when is_integer(MinLine), is_integer(MaxLine) ->
                    {ok, MinLine, MaxLine}
            end
    end.

% --------------------------------------------------------------------
% get_call_target: Call-target analysis for stepping-in, etc
% --------------------------------------------------------------------
-spec get_call_target(Line, Forms) ->
    {ok, {mfa(), Args :: [erl_syntax:syntaxTree()]}}
    | {error, Reason}
when
    Line :: line(),
    Forms :: forms(),
    Reason ::
        not_found
        | {not_a_call, Type :: atom()}
        | unsupported_operator.
get_call_target(Line, Forms) ->
    case expr_at_line(Line, Forms) of
        not_found ->
            {error, not_found};
        {ok, Expr} ->
            case erl_syntax:type(Expr) of
                application ->
                    AppOperator = erl_syntax:application_operator(Expr),
                    case erl_syntax:type(AppOperator) of
                        atom ->
                            % Call target is a local function
                            case find_module_name(Forms) of
                                {ok, M} ->
                                    F = erl_syntax:atom_value(AppOperator),
                                    Args = erl_syntax:application_arguments(Expr),
                                    A = length(Args),
                                    {ok, {{M, F, A}, Args}};
                                not_found ->
                                    {error, unsupported_operator}
                            end;
                        module_qualifier ->
                            % Call target is an MFA
                            L = erl_syntax:module_qualifier_argument(AppOperator),
                            R = erl_syntax:module_qualifier_body(AppOperator),
                            case {resolve_atom(L), resolve_atom(R)} of
                                {{ok, M}, {ok, F}} ->
                                    Args = erl_syntax:application_arguments(Expr),
                                    A = length(Args),
                                    {ok, {{M, F, A}, Args}};
                                _ ->
                                    {error, unsupported_operator}
                            end;
                        implicit_fun ->
                            % Call target is a function reference
                            Ref = erl_syntax:implicit_fun_name(AppOperator),
                            case erl_syntax:type(Ref) of
                                module_qualifier ->
                                    % fun M:F/A
                                    L = erl_syntax:module_qualifier_argument(Ref),
                                    case resolve_atom(L) of
                                        {ok, M} ->
                                            R = erl_syntax:module_qualifier_body(Ref),
                                            case resolve_arity_qualifier(M, R) of
                                                {ok, MFA} ->
                                                    Args = Args = erl_syntax:application_arguments(Expr),
                                                    {ok, {MFA, Args}};
                                                error ->
                                                    {error, unsupported_operator}
                                            end;
                                        _ ->
                                            {error, unsupported_operator}
                                    end;
                                arity_qualifier ->
                                    case find_module_name(Forms) of
                                        {ok, M} ->
                                            case resolve_arity_qualifier(M, Ref) of
                                                {ok, MFA} ->
                                                    Args = erl_syntax:application_arguments(Expr),
                                                    {ok, {MFA, Args}};
                                                error ->
                                                    {error, unsupported_operator}
                                            end;
                                        not_found ->
                                            {error, unsupported_operator}
                                    end;
                                _ ->
                                    {error, unsupported_operator}
                            end;
                        _ ->
                            {error, unsupported_operator}
                    end;
                Type ->
                    {error, {not_a_call, Type}}
            end
    end.

-spec resolve_arity_qualifier(Module, ArityQualifier) -> {ok, mfa()} | error when
    Module :: module(),
    ArityQualifier :: erl_syntax:syntaxTree().
resolve_arity_qualifier(Module, ArityQualifier) ->
    case erl_syntax:type(ArityQualifier) of
        arity_qualifier ->
            L = erl_syntax:arity_qualifier_body(ArityQualifier),
            case resolve_atom(L) of
                {ok, F} ->
                    R = erl_syntax:arity_qualifier_argument(ArityQualifier),
                    case erl_syntax:type(R) of
                        integer ->
                            A = erl_syntax:integer_value(R),
                            {ok, {Module, F, A}};
                        _ ->
                            error
                    end;
                _ ->
                    error
            end;
        _ ->
            error
    end.

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

% --------------------------------------------------------------------
% Helpers
% --------------------------------------------------------------------

-spec find_module_name(Forms) -> {ok, module()} | not_found when
    Forms :: forms().
find_module_name([]) ->
    not_found;
find_module_name([Form | Forms]) ->
    case erl_syntax:type(Form) of
        attribute ->
            L = erl_syntax:attribute_name(Form),
            Rs = erl_syntax:attribute_arguments(Form),
            case {resolve_atom(L), Rs} of
                {{ok, module}, [R]} ->
                    case resolve_atom(R) of
                        {ok, Module} -> {ok, Module};
                        _ -> find_module_name(Forms)
                    end;
                _ ->
                    find_module_name(Forms)
            end;
        _ ->
            find_module_name(Forms)
    end.

-spec find_fun_containing_line(Line, Forms) -> {ok, form()} | not_found when
    Line :: line(),
    Forms :: forms().
find_fun_containing_line(_Line, []) ->
    not_found;
find_fun_containing_line(Line, [Form, NextForm | Forms]) ->
    case erl_syntax:type(Form) of
        function ->
            NextFormLine = form_line(NextForm),
            case NextFormLine > Line of
                true ->
                    %% Next form starts after Line, so we found the function
                    {ok, Form};
                false ->
                    find_fun_containing_line(Line, [NextForm | Forms])
            end;
        _ ->
            %% Not a function form, so skip it
            find_fun_containing_line(Line, [NextForm | Forms])
    end.

-spec form_line(form()) -> line().
form_line(Form) ->
    erl_anno:line(erl_syntax:get_pos(Form)).

-spec resolve_atom(Expr :: erl_syntax:syntaxTree()) -> {ok, atom()} | none.
resolve_atom(Expr) ->
    case erl_syntax:type(Expr) of
        atom -> {ok, erl_syntax:atom_value(Expr)};
        _ -> none
    end.

-spec expr_at_line(Line, FormOrForms) -> {ok, Form} | not_found when
    Line :: line(),
    Form :: form(),
    FormOrForms :: form() | forms().
expr_at_line(_Line, []) ->
    not_found;
expr_at_line(Line, [Form | Forms]) ->
    case expr_at_line(Line, Form) of
        {ok, _} = Result ->
            Result;
        not_found ->
            expr_at_line(Line, Forms)
    end;
expr_at_line(Line, Form) ->
    case form_line(Form) =:= Line of
        true -> {ok, Form};
        false -> expr_at_line(Line, erl_syntax:subtrees(Form))
    end.
