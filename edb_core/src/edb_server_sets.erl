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

-module(edb_server_sets).
-compile(warn_missing_spec_all).

%% erlfmt:ignore
% @fb-only: -oncall("whatsapp_server_devx").

-moduledoc false.

%% Public API
-export([
    is_element/2,
    take_element/2,
    union/2, union/1,
    intersection/2,
    subtract/2,
    to_map/2,
    map_subtract_keys/2,
    is_empty/1
]).

-export_type([set/1]).

%% -------------------------------------------------------------------
%% Map-based sets
%% -------------------------------------------------------------------
-type set(A) :: #{A => term()}.

-spec is_empty(set(_)) -> boolean().
is_empty(Set) ->
    maps:size(Set) =:= 0.

-spec take_element(A, #{A => []}) -> {found, #{A => []}} | not_found.
take_element(X, Set) ->
    case maps:take(X, Set) of
        {_, Set1} -> {found, Set1};
        error -> not_found
    end.

-spec is_element(X :: A, Set :: set(A)) -> boolean().
is_element(X, Set) ->
    maps:is_key(X, Set).

-spec union(L :: set(A), R :: set(A)) -> set(A).
union(L, R) ->
    maps:merge(L, R).

-spec union([set(A)]) -> set(A).
union(Sets) ->
    lists:foldl(fun union/2, #{}, Sets).

-spec intersection(L :: set(A), R :: set(A)) -> set(A).
intersection(L, R) ->
    #{X => [] || X := _ <- L, maps:is_key(X, R)}.

-spec subtract(L :: set(A), R :: set(A)) -> set(A).
subtract(L, R) ->
    map_subtract_keys(L, R).

-spec to_map(set(K), V) -> #{K => V}.
to_map(S, V) ->
    #{K => V || K := _ <- S}.

-spec map_subtract_keys(Map :: #{K => V}, KeysToRemove :: set(K)) -> #{K => V}.
map_subtract_keys(Map, KeysToRemove) ->
    #{A => B || A := B <- Map, not is_element(A, KeysToRemove)}.
