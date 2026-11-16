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
%%% % @format

-module(eqwalizer_specs).

-oncall("whatsapp_server_devx").
-moduledoc """
eqWAlizer overrides for OTP specs, layered over the ones bundled with ELP.
""".
-export(['erts_debug:set_internal_state'/2]).

%% OTP's spec omits `debugger_support`, which the runtime accepts.
-spec 'erts_debug:set_internal_state'
    (available_internal_state, boolean()) -> boolean();
    (debugger_support, true) -> ok;
    (reds_left, non_neg_integer()) -> true;
    (block, non_neg_integer()) -> true;
    (sleep, non_neg_integer()) -> true;
    (block_scheduler, non_neg_integer()) -> true;
    (next_pid, non_neg_integer()) -> false | integer();
    (force_gc, pid() | atom()) -> boolean();
    (send_fake_exit_signal, {pid() | port(), pid(), term()}) -> dead | message | unaffected | exit;
    (colliding_names, {atom(), non_neg_integer()}) -> [atom()];
    (binary_loop_limit, default) -> -1;
    (binary_loop_limit, non_neg_integer()) -> non_neg_integer();
    (re_loop_limit, default) -> -1;
    (re_loop_limit, non_neg_integer()) -> non_neg_integer();
    (unicode_loop_limit, default) -> -1;
    (unicode_loop_limit, non_neg_integer()) -> non_neg_integer();
    (test_long_gc_sleep, non_neg_integer()) -> true;
    (kill_dist_connection, port()) -> boolean();
    (not_running_optimization, boolean()) -> boolean();
    (wait, deallocations) -> ok.
'erts_debug:set_internal_state'(_, _) -> error(eqwalizer_specs).
