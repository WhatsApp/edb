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
-export([fetch_abstract_forms/1]).
-export([get_call_targets/2]).
-export([module_source/1]).

% elp:ignore W0048 (no_dialyzer_attribute)
-dialyzer({nowarn_function, [get_debug_info/2]}).
-ignore_xref([{code, get_debug_info, 1}]).

%% --------------------------------------------------------------------
%% Types
%% --------------------------------------------------------------------

-export_type([var_debug_info/0]).

-type var_debug_info() ::
    {x, non_neg_integer()} | {y, non_neg_integer()} | {value, term()}.

-type line() :: edb:line().

%% Defined in beam_lib but not exported
-export_type([form/0, forms/0]).
-type form() :: erl_parse:abstract_form() | erl_parse:form_info().
-type forms() :: [form()].

%% --------------------------------------------------------------------
%% Debug info
%% --------------------------------------------------------------------

-spec get_debug_info(Module, Line) -> {ok, Result} | {error, Reason} when
    Module :: module(),
    Line :: pos_integer(),
    Reason :: not_found | no_debug_info | line_not_found,
    Result :: #{binary() => var_debug_info()}.
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
                {Line, {_NumSlots, VarValues}} ->
                    {ok,
                        #{
                            Var => assert_is_var_debug_info(Val)
                         || {Var, Val} <- VarValues, is_binary(Var)
                        }}
            end
    catch
        _:badarg ->
            {error, not_found}
    end.

-spec assert_is_var_debug_info(term()) -> var_debug_info().
assert_is_var_debug_info(X = {x, N}) when is_integer(N) -> X;
assert_is_var_debug_info(Y = {y, N}) when is_integer(N) -> Y;
assert_is_var_debug_info(V = {value, _}) -> V.

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
    Error :: non_existing | cover_compiled | dynamically_compiled.
fetch_beam_filename(Module) ->
    Result =
        case code:which(Module) of
            non_existing ->
                {error, non_existing};
            cover_compiled ->
                {error, cover_compiled};
            preloaded ->
                ModuleFileName = atom_to_list(Module) ++ ".beam",
                case code:where_is_file(ModuleFileName) of
                    non_existing -> {error, non_existing};
                    Filename -> {ok, Filename}
                end;
            Filename ->
                {ok, Filename}
        end,
    case Result of
        Error = {error, _} ->
            Error;
        {ok, BeamFile} ->
            case string:lowercase(filename:extension(BeamFile)) of
                ".beam" -> {ok, BeamFile};
                _ -> {error, dynamically_compiled}
            end
    end.

% --------------------------------------------------------------------
% get_call_target: Call-target analysis for stepping-in, etc
% --------------------------------------------------------------------
-spec get_call_targets(Line, Forms) ->
    {ok, nonempty_list(CallTarget)}
    | {error, Reason}
when
    Line :: line(),
    Forms :: forms(),
    CallTarget :: {mfa(), Args :: [erl_syntax:syntaxTree()]},
    Reason ::
        not_found
        | {no_call_in_expr, Type :: atom()}
        | unsupported_operator.
get_call_targets(Line, Forms) ->
    case expr_at_line(Line, Forms) of
        not_found ->
            {error, not_found};
        {ok, Expr} ->
            case find_module_name(Forms) of
                not_found ->
                    {error, not_found};
                {ok, Module} ->
                    case search_call_targets_in_exprs([Expr], Module, Line, []) of
                        {ok, []} ->
                            {error, {no_call_in_expr, erl_syntax:type(Expr)}};
                        {ok, CallTargets} ->
                            {ok, CallTargets};
                        {error, _} = Error ->
                            Error
                    end
            end
    end.

-type deep_list(A) :: [A | deep_list(A)].

-spec search_call_targets_in_exprs(Exprs, Module, Line, Acc) -> {ok, [CallTarget]} | {error, Reason} when
    Exprs :: deep_list(form()),
    Module :: module(),
    Line :: line(),
    Acc :: [CallTarget],
    CallTarget :: {mfa(), Args :: [erl_syntax:syntaxTree()]},
    Reason :: unsupported_operator.
search_call_targets_in_exprs([], _Module, _Line, Acc) ->
    {ok, Acc};
search_call_targets_in_exprs([[] | Exprs], Module, Line, Acc) ->
    search_call_targets_in_exprs(Exprs, Module, Line, Acc);
search_call_targets_in_exprs([[Expr | Exprs0] | Exprs1], Module, Line, Acc) ->
    search_call_targets_in_exprs([Expr | [Exprs0 | Exprs1]], Module, Line, Acc);
search_call_targets_in_exprs([Expr | Exprs0], Module, Line, Acc) ->
    Result =
        case erl_syntax:type(Expr) of
            application ->
                AppOperator = erl_syntax:application_operator(Expr),
                case erl_syntax:type(AppOperator) of
                    atom ->
                        % Call target is a local function
                        F = erl_syntax:atom_value(AppOperator),
                        Args = erl_syntax:application_arguments(Expr),
                        A = length(Args),
                        {ok, {{Module, F, A}, Args}};
                    module_qualifier ->
                        % Call target is an MFA
                        maybe
                            L = erl_syntax:module_qualifier_argument(AppOperator),
                            R = erl_syntax:module_qualifier_body(AppOperator),
                            {{ok, M}, {ok, F}} ?= {resolve_atom(L), resolve_atom(R)},
                            Args = erl_syntax:application_arguments(Expr),
                            A = length(Args),
                            {ok, {{M, F, A}, Args}}
                        else
                            _ -> {error, unsupported_operator}
                        end;
                    implicit_fun ->
                        % Call target is a function reference
                        Ref = erl_syntax:implicit_fun_name(AppOperator),
                        case erl_syntax:type(Ref) of
                            module_qualifier ->
                                % fun M:F/A
                                L = erl_syntax:module_qualifier_argument(Ref),
                                maybe
                                    {ok, M} ?= resolve_atom(L),
                                    R = erl_syntax:module_qualifier_body(Ref),
                                    {ok, MFA} ?= resolve_arity_qualifier(M, R),
                                    Args = erl_syntax:application_arguments(Expr),
                                    {ok, {MFA, Args}}
                                else
                                    _ -> {error, unsupported_operator}
                                end;
                            arity_qualifier ->
                                maybe
                                    {ok, MFA} ?= resolve_arity_qualifier(Module, Ref),
                                    Args = erl_syntax:application_arguments(Expr),
                                    {ok, {MFA, Args}}
                                else
                                    error ->
                                        {error, unsupported_operator}
                                end;
                            _ ->
                                {error, unsupported_operator}
                        end;
                    _ ->
                        {error, unsupported_operator}
                end;
            _ ->
                not_found
        end,
    case Result of
        not_found ->
            Candidates = [Cand || Cand <- get_candidate_call_target_subexprs(Expr), form_line(Cand) =:= Line],
            Exprs1 = [Candidates | Exprs0],
            search_call_targets_in_exprs(Exprs1, Module, Line, Acc);
        {ok, CallTarget} ->
            search_call_targets_in_exprs(Exprs0, Module, Line, [CallTarget | Acc]);
        Error = {error, _} ->
            Error
    end.

-spec get_candidate_call_target_subexprs(Expr) -> [Expr] when Expr :: form().
get_candidate_call_target_subexprs(Expr) ->
    case erl_syntax:type(Expr) of
        block_expr ->
            first_form_only(erl_syntax:block_expr_body(Expr));
        case_expr ->
            [erl_syntax:case_expr_argument(Expr)];
        catch_expr ->
            [erl_syntax:catch_expr_body(Expr)];
        generator ->
            [erl_syntax:generator_body(Expr)];
        infix_expr ->
            [erl_syntax:infix_expr_left(Expr), erl_syntax:infix_expr_right(Expr)];
        list ->
            Prefix = erl_syntax:list_prefix(Expr),
            case erl_syntax:list_suffix(Expr) of
                none -> Prefix;
                Suffix -> [Suffix | Prefix]
            end;
        map_expr ->
            erl_syntax:map_expr_fields(Expr);
        map_field_assoc ->
            [erl_syntax:map_field_assoc_name(Expr), erl_syntax:map_field_assoc_value(Expr)];
        map_generator ->
            [erl_syntax:map_generator_body(Expr)];
        match_expr ->
            [erl_syntax:match_expr_body(Expr)];
        maybe_expr ->
            first_form_only(erl_syntax:maybe_expr_body(Expr));
        maybe_match_expr ->
            [erl_syntax:maybe_match_expr_body(Expr)];
        record_expr ->
            erl_syntax:record_expr_fields(Expr);
        record_field ->
            [erl_syntax:record_field_value(Expr)];
        tuple ->
            erl_syntax:tuple_elements(Expr);
        try_expr ->
            first_form_only(erl_syntax:try_expr_body(Expr));
        _ ->
            []
    end.

-spec first_form_only(Forms) -> Forms when Forms :: [form()].
first_form_only(Forms) -> lists:sublist(Forms, 1).

-spec resolve_arity_qualifier(Module, ArityQualifier) -> {ok, mfa()} | error when
    Module :: module(),
    ArityQualifier :: erl_syntax:syntaxTree().
resolve_arity_qualifier(Module, ArityQualifier) ->
    maybe
        arity_qualifier ?= erl_syntax:type(ArityQualifier),
        L = erl_syntax:arity_qualifier_body(ArityQualifier),
        {ok, F} ?= resolve_atom(L),
        R = erl_syntax:arity_qualifier_argument(ArityQualifier),
        integer ?= erl_syntax:type(R),
        A = erl_syntax:integer_value(R),
        {ok, {Module, F, A}}
    else
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
    maybe
        attribute ?= erl_syntax:type(Form),
        L = erl_syntax:attribute_name(Form),
        Rs = erl_syntax:attribute_arguments(Form),
        {{ok, module}, [R]} ?= {resolve_atom(L), Rs},
        {ok, _Module} ?= resolve_atom(R)
    else
        _ -> find_module_name(Forms)
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
