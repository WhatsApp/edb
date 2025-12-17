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
%%
-module(edb_dap_utils_SUITE).

%% erlfmt:ignore
% @fb-only: -oncall("whatsapp_server_devx").

-include_lib("assert/include/assert.hrl").

%% Test server callbacks
-export([
    all/0,
    suite/0,
    init_per_testcase/2,
    end_per_testcase/2
]).

%% Test cases
-export([
    strip_suffix/1
]).

all() ->
    [
        strip_suffix
    ].

%% erlfmt:ignore fb-only needs to be on same line
suite() ->
    [
        % @fb-only: {wa_ct_log_sentinel, #{enable => true, enable_zero_error_logs_check => true}}
    ].

init_per_testcase(_TestCase, Config) ->
    Config.

end_per_testcase(_TestCase, _Config) ->
    ok.

strip_suffix(_Config) ->
    ?assertEqual(<<"/my/repo/my/">>, edb_dap_utils:strip_suffix(<<"/my/repo/my/">>, <<"app">>)),
    ?assertEqual(<<"/my/repo/">>, edb_dap_utils:strip_suffix(<<"/my/repo/my/app">>, <<"my/app">>)),
    ?assertEqual(<<"/my/repo">>, edb_dap_utils:strip_suffix(<<"/my/repo/my/app">>, <<"/my/app">>)),
    ?assertEqual(<<"/my/repo/my/app">>, edb_dap_utils:strip_suffix(<<"/my/repo/my/app">>, <<"my_app">>)).
