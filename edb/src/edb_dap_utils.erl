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
%%%-------------------------------------------------------------------
%% @doc DAP Request Handlers
%%      The actual implementation for the DAP requests.
%%      This function should be invoked by the DAP server.
%% @end
%%%-------------------------------------------------------------------
%%% % @format

-module(edb_dap_utils).

%% erlfmt:ignore
% @fb-only: 
-compile(warn_missing_spec_all).

-export([strip_suffix/2]).

-spec strip_suffix(binary(), binary()) -> binary().
strip_suffix(Path, Suffix) ->
    SuffixSize = byte_size(Suffix),
    PathSize = byte_size(Path),
    case binary:part(Path, {PathSize, -SuffixSize}) of
        Suffix -> binary:part(Path, {0, PathSize - SuffixSize});
        _ -> Path
    end.
