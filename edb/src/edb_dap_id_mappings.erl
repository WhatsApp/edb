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

-module(edb_dap_id_mappings).

%% erlfmt:ignore
% @fb-only
-moduledoc """
An mapper of IDs for the debug adapter

The DAP protocol expects numeric ids for threads, frames, scopes, etc. These ids
are represented as number() in the JSON specification, and are expected to fit
in a 64-bit float. Some ids like thread_ids are expected to be unique across the
debugging session, while others (frame-ids, etc), need be unique only between
pauses. The specification recommends adapters to reset them on `continue` requests.
For more details see https://microsoft.github.io/debug-adapter-protocol/overview

This module implements the mapping fo PIDs to thread-ids, etc, generically.

""".
-compile(warn_missing_spec_all).

-behaviour(gen_server).

%% API
-export([start_link_thread_ids_server/0, start_link_frame_ids_server/0, start_link_var_reference_ids_server/0]).
-export([pid_to_thread_id/1, pids_to_thread_ids/1, thread_id_to_pid/1]).
-export([pid_frame_to_frame_id/1, frame_id_to_pid_frame/1]).
-export([var_reference_to_frame_scope_or_structured/1, frame_scope_or_structured_to_var_reference/1]).
-export([reset/0]).

%% gen_server callbacks
-export([
    init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2
]).

-export_type([id/0]).
-export_type([pid_frame/0]).
-export_type([frame_scope/0]).
-export_type([structured/0]).
-export_type([frame_scope_or_structured/0]).

%% @doc An integer that fits in a 64-bit float
%%
%% This is the requirement the DAP spec puts on ids.
-type id() :: non_neg_integer().

-type pid_frame() :: #{pid := pid(), frame_no := non_neg_integer()}.
-type scope() :: locals | registers | messages.
-type frame_scope_or_structured() :: frame_scope() | structured().
-type frame_scope() :: #{frame := id(), scope := scope()}.
-type structured() :: #{elements := [{binary(), edb:value()}]}.

-type state(A) :: id_mapping(A).

-define(THREAD_IDS_SERVER, edb_dap_thread_id_mappings).
-define(FRAME_IDS_SERVER, edb_dap_frame_id_mappings).
-define(VAR_REFERENCE_IDS_SERVER, edb_dap_var_reference_id_mappings).

%%%---------------------------------------------------------------------------------
%%% API
%%%---------------------------------------------------------------------------------

-spec start_link_thread_ids_server() -> gen_server:start_ret().
start_link_thread_ids_server() ->
    gen_server:start_link({local, ?THREAD_IDS_SERVER}, ?MODULE, ?THREAD_IDS_SERVER, []).

-spec start_link_frame_ids_server() -> gen_server:start_ret().
start_link_frame_ids_server() ->
    gen_server:start_link({local, ?FRAME_IDS_SERVER}, ?MODULE, ?FRAME_IDS_SERVER, []).

-spec start_link_var_reference_ids_server() -> gen_server:start_ret().
start_link_var_reference_ids_server() ->
    gen_server:start_link({local, ?VAR_REFERENCE_IDS_SERVER}, ?MODULE, ?VAR_REFERENCE_IDS_SERVER, []).

-spec pid_to_thread_id(pid()) -> id().
pid_to_thread_id(Pid) when is_pid(Pid) ->
    gen_server:call(?THREAD_IDS_SERVER, {get_id, Pid}).

-spec pids_to_thread_ids([pid()]) -> #{pid() => id()}.
pids_to_thread_ids(Pids) ->
    gen_server:call(?THREAD_IDS_SERVER, {get_ids, Pids}).

-spec thread_id_to_pid(id()) -> {ok, pid()} | {error, not_found}.
thread_id_to_pid(Id) when is_integer(Id) ->
    gen_server:call(?THREAD_IDS_SERVER, {from_id, Id}).

-spec pid_frame_to_frame_id(pid_frame()) -> id().
pid_frame_to_frame_id(FrameId = #{pid := Pid, frame_no := No}) when is_pid(Pid), is_integer(No) ->
    gen_server:call(?FRAME_IDS_SERVER, {get_id, FrameId}).

-spec frame_id_to_pid_frame(id()) -> {ok, pid_frame()} | {error, not_found}.
frame_id_to_pid_frame(Id) when is_integer(Id) ->
    gen_server:call(?FRAME_IDS_SERVER, {from_id, Id}).

-spec frame_scope_or_structured_to_var_reference(frame_scope_or_structured()) -> id().
frame_scope_or_structured_to_var_reference(#{elements := Elements} = Structured) when is_list(Elements) ->
    gen_server:call(?VAR_REFERENCE_IDS_SERVER, {get_id, Structured});
frame_scope_or_structured_to_var_reference(#{frame := Id, scope := Scope} = FrameScope) when
    is_integer(Id), is_atom(Scope)
->
    gen_server:call(?VAR_REFERENCE_IDS_SERVER, {get_id, FrameScope}).

-spec var_reference_to_frame_scope_or_structured(id()) -> {ok, frame_scope_or_structured()} | {error, not_found}.
var_reference_to_frame_scope_or_structured(VarReference) when is_integer(VarReference) ->
    gen_server:call(?VAR_REFERENCE_IDS_SERVER, {from_id, VarReference}).

-spec reset() -> ok.
reset() ->
    % NB. thread-ids are persistent, so don't reset them
    gen_server:call(?FRAME_IDS_SERVER, reset).

%%%---------------------------------------------------------------------------------
%%% Callbacks
%%%---------------------------------------------------------------------------------

-spec init
    (?THREAD_IDS_SERVER) -> {ok, state(pid())};
    (?FRAME_IDS_SERVER) -> {ok, state(pid_frame())};
    (?VAR_REFERENCE_IDS_SERVER) -> {ok, state(id())}.
init(ServerType) ->
    Validator =
        case ServerType of
            ?THREAD_IDS_SERVER ->
                fun
                    (Pid) when is_pid(Pid) -> {ok, Pid};
                    (_) -> invalid
                end;
            ?FRAME_IDS_SERVER ->
                fun
                    (FrameId = #{pid := Pid, frame_no := No}) when is_pid(Pid), is_integer(No) ->
                        {ok, FrameId};
                    (_) ->
                        invalid
                end;
            ?VAR_REFERENCE_IDS_SERVER ->
                fun
                    (VarReference = #{frame := FrameId, scope := Scope}) when is_integer(FrameId), is_atom(Scope) ->
                        {ok, VarReference};
                    (VarReference = #{elements := Elements}) when is_list(Elements) ->
                        {ok, VarReference};
                    (_) ->
                        invalid
                end
        end,
    State = empty_id_mapping(Validator),
    {ok, State}.

-spec handle_call
    ({get_id, A}, gen_server:from(), state(A)) -> {reply, id(), state(A)};
    ({get_ids, [A]}, gen_server:from(), state(A)) -> {reply, #{A => id()}, state(A)};
    ({from_id, id()}, gen_server:from(), state(A)) -> {reply, {ok, A} | {error, not_found}, state(A)};
    (reset, gen_server:from(), state(A)) -> {reply, ok, state(A)}.
handle_call({get_id, A}, _From, State0) ->
    {Id, State1} = id_mapping_get_id(A, State0),
    {reply, Id, State1};
handle_call({get_ids, As}, _From, State0) ->
    {Ids, State1} = lists:foldl(
        fun(A, {IdsN, StateN}) ->
            {Id, StateN_plus_1} = id_mapping_get_id(A, StateN),
            IdsN_plus_1 = IdsN#{A => Id},
            {IdsN_plus_1, StateN_plus_1}
        end,
        {#{}, State0},
        As
    ),
    {reply, Ids, State1};
handle_call({from_id, Id}, _From, State0) ->
    Result = id_mapping_from_id(Id, State0),
    {reply, Result, State0};
handle_call(reset, _From, State0) ->
    State1 = id_mapping_reset(State0),
    {reply, ok, State1}.

-spec handle_cast(term(), state(A)) -> {noreply, state(A)}.
handle_cast(_Request, State) ->
    {noreply, State}.

-spec handle_info(term(), state(A)) -> {noreply, state(A)}.
handle_info(_, State) ->
    {noreply, State}.

%%%---------------------------------------------------------------------------------
%%% Mappings
%%%---------------------------------------------------------------------------------

-type validator(A) :: fun((term()) -> {ok, A} | invalid).

-type id_mapping(A) :: #{
    validator := validator(A),
    back := #{id() => A},
    forth := #{A => id()},
    next := id()
}.

-spec empty_id_mapping(validator(A)) -> id_mapping(A).
empty_id_mapping(Validator) ->
    #{
        validator => Validator,
        back => #{},
        forth => #{},
        next => 1
    }.

-spec id_mapping_get_id(A, id_mapping(A)) -> {id(), id_mapping(A)}.
id_mapping_get_id(A, M0) when is_map(M0) ->
    #{validator := Valid, back := Back, forth := Forth, next := Next} = M0,
    case Valid(A) of
        {ok, A} ->
            case maps:get(A, Forth, undefined) of
                Id when is_integer(Id) ->
                    {Id, M0};
                undefined ->
                    Id = Next,
                    M1 = M0#{
                        back => Back#{Id => A},
                        forth => Forth#{A => Id},
                        next => Next + 1
                    },
                    {Id, M1}
            end
    end.

-spec id_mapping_from_id(id(), id_mapping(A)) -> {ok, A} | {error, not_found}.
id_mapping_from_id(Id, M) ->
    #{back := Back} = M,
    case Back of
        #{Id := A} ->
            {ok, A};
        #{} ->
            {error, not_found}
    end.

-spec id_mapping_reset(id_mapping(A)) -> id_mapping(A).
id_mapping_reset(M) ->
    #{validator := Validator} = M,
    empty_id_mapping(Validator).
