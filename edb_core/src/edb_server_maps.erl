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

-module(edb_server_maps).
-compile(warn_missing_spec_all).

%% erlfmt:ignore
% @fb-only

-moduledoc false.

%% Public API
-export([add/3, add/4, add/5, add/6]).
-export([remove/2, remove/3, remove/4, remove/5]).

-spec add(Key, Value, Map) -> Map when
    Map :: #{Key => Value}.
add(Key, Value, Map) ->
    Map#{Key => Value}.

-spec add(Key1, Key2, Value, Map) -> Map when
    Map :: #{Key1 => #{Key2 => Value}}.
add(Key1, Key2, Value, Map) ->
    maps:update_with(
        Key1,
        fun(Map1) -> add(Key2, Value, Map1) end,
        #{Key2 => Value},
        Map
    ).

-spec add(Key1, Key2, Key3, Value, Map) -> Map when
    Map :: #{Key1 => #{Key2 => #{Key3 => Value}}}.
add(Key1, Key2, Key3, Value, Map) ->
    maps:update_with(
        Key1,
        fun(Map1) -> add(Key2, Key3, Value, Map1) end,
        #{Key2 => #{Key3 => Value}},
        Map
    ).

-spec add(Key1, Key2, Key3, Key4, Value, Map) -> Map when
    Map :: #{Key1 => #{Key2 => #{Key3 => #{Key4 => Value}}}}.
add(Key1, Key2, Key3, Key4, Value, Map) ->
    maps:update_with(
        Key1,
        fun(Map1) -> add(Key2, Key3, Key4, Value, Map1) end,
        #{Key2 => #{Key3 => #{Key4 => Value}}},
        Map
    ).

-spec remove(Key, Map0) -> Map1 when
    Map0 :: #{Key => Value},
    Map1 :: #{Key => Value}.
remove(Key, Map) ->
    maps:remove(Key, Map).

-spec remove(Key1, Key2, Map0) -> Map1 when
    Map0 :: #{Key1 => #{Key2 => Value}},
    Map1 :: #{Key1 => #{Key2 => Value}}.
remove(Key1, Key2, Map) ->
    case maps:find(Key1, Map) of
        {ok, Map1} ->
            NewMap1 = remove(Key2, Map1),
            case maps:size(NewMap1) of
                0 -> maps:remove(Key1, Map);
                _ -> Map#{Key1 := NewMap1}
            end;
        error ->
            Map
    end.

-spec remove(Key1, Key2, Key3, Map0) -> Map1 when
    Map0 :: #{Key1 => #{Key2 => #{Key3 => Value}}},
    Map1 :: #{Key1 => #{Key2 => #{Key3 => Value}}}.
remove(Key1, Key2, Key3, Map) ->
    case maps:find(Key1, Map) of
        {ok, Map1} ->
            NewMap1 = remove(Key2, Key3, Map1),
            case maps:size(NewMap1) of
                0 -> maps:remove(Key1, Map);
                _ -> Map#{Key1 := NewMap1}
            end;
        error ->
            Map
    end.

-spec remove(Key1, Key2, Key3, Key4, Map0) -> Map1 when
    Map0 :: #{Key1 => #{Key2 => #{Key3 => #{Key4 => Value}}}},
    Map1 :: #{Key1 => #{Key2 => #{Key3 => #{Key4 => Value}}}}.
remove(Key1, Key2, Key3, Key4, Map) ->
    case maps:find(Key1, Map) of
        {ok, Map1} ->
            NewMap1 = remove(Key2, Key3, Key4, Map1),
            case maps:size(NewMap1) of
                0 -> maps:remove(Key1, Map);
                _ -> Map#{Key1 := NewMap1}
            end;
        error ->
            Map
    end.
