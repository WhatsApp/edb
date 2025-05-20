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
%%%---------------------------------------------------------------------------------
%%% % @format

-module(edb_dap_eval_delegate).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-moduledoc """
This module handles all the calls to edb:eval/1, and all callbacks
are defined here. Because of that, this module will end up being
transferred to the debuggee node, so the callbacks can be executed.

It is very important that this has no dependencies on anything other
than kernel, stdlib and edb_core, as those are the only apps that can
be assumed to be running on the debuggee.
""".

% Running
-export([eval/1]).

% Callbacks
-export([scopes_callback/1]).
-export([structure_callback/2]).
-export([evaluate_callback/1]).

% Helpers
-export([slice_list/2]).

% -----------------------------------------------------------------------------
% Types
% -----------------------------------------------------------------------------
-opaque callback(Result) ::
    #{
        function := stack_frame_vars_fun(Result),
        deps := [module()]
    }.
-export_type([callback/1]).

-type stack_frame_vars_fun(Result) :: fun((Vars :: edb:stack_frame_vars()) -> Result).

-type scope() :: #{
    type := process | locals | registers,
    variables := [variable()]
}.

-type variable() :: #{
    name := binary(),
    value_rep := binary(),
    structure :=
        none | structure()
}.

-type evaluation_result() ::
    #{
        type := success,
        value_rep := binary(),
        structure :=
            none | structure()
    }
    | #{
        type := exception,
        class := error | exit | throw,
        reason := term(),
        stacktrace := erlang:stacktrace()
    }.

-type structure() :: #{
    count := pos_integer(),
    accessor := accessor()
}.

-opaque accessor() :: stack_frame_vars_fun(term()).

-type window() :: #{start := pos_integer(), count := non_neg_integer() | infinity}.

-export_type([scope/0, variable/0, evaluation_result/0, structure/0, accessor/0, window/0]).

% -----------------------------------------------------------------------------
% Running
% -----------------------------------------------------------------------------

-spec eval(Opts) ->
    not_paused | undefined | {ok, Result} | {eval_error, edb:eval_error()}
when
    Opts :: #{
        context := {pid(), edb:frame_id()},
        max_term_size => non_neg_integer(),
        timeout => timeout(),
        function := callback(Result)
    }.
eval(Opts0) ->
    #{function := #{function := Fun, deps := Deps}} = Opts0,
    Opts1 = Opts0#{function => Fun, dependencies => Deps},
    Defaults = #{
        max_term_size => 1_000_000_000,
        timeout => 5_000
    },
    Opts2 = maps:merge(Defaults, Opts1),
    % eqwalizer:fixme spec of maps:merge() loses info
    edb:eval(Opts2).

% -----------------------------------------------------------------------------
% Callback for the "scopes" request
% -----------------------------------------------------------------------------
-spec scopes_callback(Pid) -> callback([scope()]) when
    Pid :: pid().
scopes_callback(Pid) ->
    #{
        deps => [],
        function =>
            fun(StackFrameVars) ->
                Scopes0 = [process_scope(Pid)],
                Scopes1 =
                    case StackFrameVars of
                        #{vars := Vars} ->
                            [locals_scope(Vars) | Scopes0];
                        _ ->
                            [registers_scope(StackFrameVars) | Scopes0]
                    end,
                Scopes1
            end
    }.

-spec locals_scope(Vars) -> scope() when
    Vars :: #{Name :: binary() => edb:value()}.
locals_scope(Vars) ->
    #{
        type => locals,
        variables => [
            #{
                name => Name,
                value_rep => value_rep(Value),
                structure => structure(Value, access_local(Name))
            }
         || Name := Value <- Vars
        ]
    }.

-spec access_local(Name) -> accessor() when Name :: binary().
access_local(Name) ->
    fun(#{vars := Vars}) ->
        case Vars of
            #{Name := {value, Value}} -> Value
        end
    end.

-spec registers_scope(StackFrameVars) -> scope() when
    StackFrameVars :: edb:stack_frame_vars().
registers_scope(StackFrameVars) ->
    #{
        type => registers,
        variables => [
            #{
                name => format("~s~p", [Prefix, RegIdx]),
                value_rep => value_rep(RegValue),
                structure => structure(RegValue, access_reg(RegType, RegIdx))
            }
         || {RegType, Prefix} <- [{xregs, ~"X"}, {yregs, ~"Y"}],
            {RegIdx, RegValue} <- lists:enumerate(0, maps:get(RegType, StackFrameVars, []))
        ]
    }.

-spec access_reg(Type, Index) -> accessor() when
    Type :: xregs | yregs,
    Index :: non_neg_integer().
access_reg(Type, Index) ->
    fun(StackFrameVars) ->
        {value, Value} = lists:nth(Index + 1, maps:get(Type, StackFrameVars)),
        Value
    end.

-spec process_scope(Pid) -> scope() when Pid :: pid().
process_scope(Pid) ->
    MessagesVar =
        case erlang:process_info(Pid, messages) of
            {messages, Messages} ->
                [
                    #{
                        name => ~"Messages in queue",
                        value_rep => format("~p", [length(Messages)]),
                        structure => structure({value, Messages}, access_process_info(Pid, messages))
                    }
                ];
            _ ->
                []
        end,
    #{type => process, variables => MessagesVar}.

-spec access_process_info(Pid, Type) -> accessor() when
    Pid :: pid(),
    Type :: messages.
access_process_info(Pid, Type) ->
    fun(_) ->
        {Type, Value} = erlang:process_info(Pid, Type),
        Value
    end.

% -----------------------------------------------------------------------------
% Callback for the "variables" request
% -----------------------------------------------------------------------------
-spec structure_callback(Accessor, Window) -> callback([variable()]) when
    Accessor :: accessor(),
    Window :: window().
structure_callback(Accessor, Window) ->
    #{
        deps => [],
        function =>
            fun(StackFrameVars) ->
                case Accessor(StackFrameVars) of
                    List when is_list(List) -> list_structure(List, Accessor, Window);
                    Tuple when is_tuple(Tuple) -> tuple_structure(Tuple, Accessor, Window);
                    Map when is_map(Map) -> map_structure(Map, Accessor, Window);
                    _ -> []
                end
            end
    }.

-spec list_structure(List, Accessor, Window) -> [variable()] when
    List :: list(),
    Accessor :: accessor(),
    Window :: window().
list_structure(List, Accessor, Window = #{start := Start}) ->
    ListWindow = slice_list(List, Window),
    [
        #{
            name => integer_to_binary(Index),
            value_rep => value_rep({value, Value}),
            structure => structure({value, Value}, extend_accessor(Accessor, Step))
        }
     || {Index, Value} <- lists:enumerate(Start, ListWindow),
        Step <- [fun(L) -> lists:nth(Index, L) end]
    ].

-spec slice_list(List, Window) -> Slice when
    List :: [A],
    Window :: window(),
    Slice :: [A].
slice_list(List, #{start := 1, count := infinity}) -> List;
slice_list(List, #{start := Start, count := infinity}) -> lists:nthtail(Start, List);
slice_list(List, #{start := Start, count := Count}) -> lists:sublist(List, Start, Count).

-spec tuple_structure(Tuple, Accessor, Window) -> [variable()] when
    Tuple :: tuple(),
    Accessor :: accessor(),
    Window :: window().
tuple_structure(Tuple, Accessor, Window) ->
    Indices =
        case Window of
            #{start := Start, count := infinity} ->
                lists:seq(Start, tuple_size(Tuple));
            #{start := Start, count := Count} ->
                End = min(tuple_size(Tuple), Start + Count - 1),
                lists:seq(Start, End)
        end,
    [
        #{
            name => integer_to_binary(Index),
            value_rep => value_rep({value, Value}),
            structure => structure({value, Value}, extend_accessor(Accessor, Step))
        }
     || Index <- Indices,
        Value <- [erlang:element(Index, Tuple)],
        Step <- [fun(T) -> erlang:element(Index, T) end]
    ].

-spec map_structure(Map, Accessor, Window) -> [variable()] when
    Map :: map(),
    Accessor :: accessor(),
    Window :: window().
map_structure(Map, Accessor, #{start := Start, count := Count}) ->
    Slice = slice_map_iterator(maps:iterator(Map, ordered), Start, Count),
    [
        #{
            name => value_rep({value, Key}),
            value_rep => value_rep({value, Value}),
            structure => structure({value, Value}, extend_accessor(Accessor, Step))
        }
     || {Key, Value} <- Slice,
        Step <- [fun(M) -> maps:get(Key, M) end]
    ].

-spec slice_map_iterator(Iterator, Start, Len) -> Slice when
    Iterator :: maps:iterator(K, V),
    Start :: pos_integer(),
    Len :: non_neg_integer() | infinity,
    Slice :: [{K, V}].
slice_map_iterator(_Iterator, _, 0) ->
    [];
slice_map_iterator(Iterator0, Start, Count) when Start > 1 ->
    case maps:next(Iterator0) of
        none -> [];
        {_K, _V, Iterator1} -> slice_map_iterator(Iterator1, Start - 1, Count)
    end;
slice_map_iterator(Iterator0, 1, infinity) ->
    maps:to_list(Iterator0);
slice_map_iterator(Iterator0, 1, Count) when is_integer(Count) ->
    case maps:next(Iterator0) of
        none -> [];
        {K, V, Iterator1} -> [{K, V} | slice_map_iterator(Iterator1, 1, Count - 1)]
    end.

-spec extend_accessor(Accessor, Step) -> accessor() when
    Accessor :: accessor(),
    Step :: fun((term()) -> term()).
extend_accessor(Accessor, Step) ->
    fun(StackFrameVars) -> Step(Accessor(StackFrameVars)) end.

% -----------------------------------------------------------------------------
% Callback for the "evaluate" request
% -----------------------------------------------------------------------------
-spec evaluate_callback(CompiledExpr) -> callback(evaluation_result()) when
    CompiledExpr :: edb_expr:compiled_expr().
evaluate_callback(CompiledExpr) ->
    Eval = edb_expr:entrypoint(CompiledExpr),
    #{
        deps => [maps:get(module, CompiledExpr)],
        function =>
            fun(StackFrameVars) ->
                try Eval(StackFrameVars) of
                    Result ->
                        #{
                            type => success,
                            value_rep => value_rep({value, Result}),
                            structure => structure({value, Result}, Eval)
                        }
                catch
                    EClass:EReason:ST ->
                        #{
                            type => exception,
                            class => EClass,
                            reason => EReason,
                            stacktrace => ST
                        }
                end
            end
    }.

% -----------------------------------------------------------------------------
% Helpers
% -----------------------------------------------------------------------------

-spec value_rep(Val) -> binary() when
    Val :: edb:value().
value_rep({value, Value}) ->
    format("~0kp", [Value]);
value_rep({too_large, Size, Max}) ->
    format("Too Large (~p vs ~p)", [Size, Max]).

-spec format(Format, Args) -> binary() when
    Format :: io:format(),
    Args :: [term()].
format(Format, Args) ->
    case io_lib:format(Format, Args) of
        Chars when is_list(Chars) ->
            String = lists:flatten(Chars),
            case unicode:characters_to_binary(String) of
                Binary when is_binary(Binary) -> Binary
            end
    end.

-spec structure(Val, ValAccessor) -> none | structure() when
    Val :: edb:value(),
    ValAccessor :: accessor().
structure({value, Val = [_ | _]}, ValAccessor) ->
    #{
        count => length(Val),
        accessor => ValAccessor
    };
structure({value, Val}, ValAccessor) when is_tuple(Val), tuple_size(Val) > 0 ->
    #{
        count => tuple_size(Val),
        accessor => ValAccessor
    };
structure({value, Val}, ValAccessor) when is_map(Val), map_size(Val) > 0 ->
    #{
        count => map_size(Val),
        accessor => ValAccessor
    };
structure(_, _ValAccessor) ->
    none.
