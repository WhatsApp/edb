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

% -----------------------------------------------------------------------------
% Types
% -----------------------------------------------------------------------------
-opaque callback(Result) :: fun((Vars :: edb:stack_frame_vars()) -> Result).
-export_type([callback/1]).

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

-type structure() :: #{
    type := named | indexed,
    count := pos_integer(),
    accessor := accessor()
}.

-opaque accessor() :: callback(term()).

-type window() :: #{start := pos_integer(), count := non_neg_integer()}.

-export_type([scope/0, variable/0, structure/0, accessor/0, window/0]).

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
    Defaults = #{
        max_term_size => 1_000_000,
        timeout => 5_000
    },
    Opts1 = maps:merge(Defaults, Opts0),
    % eqwalizer:fixme spec of maps:merge() loses info
    edb:eval(Opts1).

% -----------------------------------------------------------------------------
% Callback for the "scopes" request
% -----------------------------------------------------------------------------
-spec scopes_callback(Pid) -> callback([scope()]) when
    Pid :: pid().
scopes_callback(Pid) ->
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
    end.

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
    fun(StackFrameVars) ->
        case Accessor(StackFrameVars) of
            List when is_list(List) -> list_structure(List, Accessor, Window);
            Tuple when is_tuple(Tuple) -> tuple_structure(Tuple, Accessor, Window);
            Map when is_map(Map) -> map_structure(Map, Accessor, Window);
            _ -> []
        end
    end.

-spec list_structure(List, Accessor, Window) -> [variable()] when
    List :: list(),
    Accessor :: accessor(),
    Window :: window().
list_structure(List, Accessor, #{start := Start, count := Count}) ->
    ListWindow = lists:sublist(List, Start, Count),
    [
        #{
            name => integer_to_binary(Index),
            value_rep => value_rep({value, Value}),
            structure => structure({value, Value}, extend_accessor(Accessor, Step))
        }
     || {Index, Value} <- lists:enumerate(ListWindow),
        Step <- [fun(L) -> lists:nth(Index, L) end]
    ].

-spec tuple_structure(Tuple, Accessor, Window) -> [variable()] when
    Tuple :: tuple(),
    Accessor :: accessor(),
    Window :: window().
tuple_structure(Tuple, Accessor, #{start := Start, count := Count}) ->
    [
        #{
            name => integer_to_binary(Index),
            value_rep => value_rep({value, Value}),
            structure => structure({value, Value}, extend_accessor(Accessor, Step))
        }
     || Index <- lists:seq(Start, Count),
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
    Len :: non_neg_integer(),
    Slice :: [{K, V}].
slice_map_iterator(_Iterator, _, 0) ->
    [];
slice_map_iterator(Iterator0, Start, Count) when Start > 1 ->
    case maps:next(Iterator0) of
        none -> [];
        {_K, _V, Iterator1} -> slice_map_iterator(Iterator1, Start - 1, Count)
    end;
slice_map_iterator(Iterator0, 1, Count) ->
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
% Helpers
% -----------------------------------------------------------------------------

-spec value_rep(Val) -> binary() when
    Val :: edb:value().
value_rep({value, Value}) ->
    format("~p", [Value]);
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
    ValAccessor :: callback(term()).
structure({value, Val = [_ | _]}, ValAccessor) ->
    #{
        type => indexed,
        count => length(Val),
        accessor => ValAccessor
    };
structure({value, Val}, ValAccessor) when is_tuple(Val), tuple_size(Val) > 0 ->
    #{
        type => indexed,
        count => tuple_size(Val),
        accessor => ValAccessor
    };
structure({value, Val}, ValAccessor) when is_map(Val), map_size(Val) > 0 ->
    #{
        type => named,
        count => map_size(Val),
        accessor => ValAccessor
    };
structure(_, _ValAccessor) ->
    none.
