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
-module(edb_main).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-export([main/1]).

-spec main([string()]) -> term().
main(Args) ->
    argparse:run(Args, command(), #{progname => "edb"}).

-spec command() -> argparse:command().
command() ->
    #{
        commands => commands(),
        arguments => [],
        help => "The Erlang Debugger"
    }.

-spec commands() -> #{string() => argparse:command()}.
commands() ->
    #{
        "dap" => dap_command()
    }.

-spec dap_command() -> argparse:command().
dap_command() ->
    #{
        arguments => [],
        handler => fun dap_handler/1,
        help => "Start a DAP server"
    }.

-spec dap_handler(argparse:arg_map()) -> term().
dap_handler(_Args) ->
    configure_dap_logging(),
    Ref = erlang:make_ref(),
    Me = self(),
    App = edb,
    application:set_env(App, on_exit, fun() -> Me ! {exit, Ref} end, [{persistent, true}]),
    {ok, _} = application:ensure_all_started(App, permanent),
    receive
        {exit, Ref} ->
            application:stop(App),
            ok
    end.

-define(LOG_FORMAT, [
    "[", time, "] ", "[", level, "] ", msg, " [", mfa, " L", line, "] ", pid, "\n"
]).
-define(LOG_LEVEL, info).
-define(LOG_MAX_NO_BYTES, 10 * 1000 * 1000).
-define(LOG_MAX_NO_FILES, 5).

-spec configure_dap_logging() -> ok.
configure_dap_logging() ->
    LogDir = filename:basedir(user_log, "edb"),
    LogFile = filename:join([LogDir, "edb.log"]),
    ok = filelib:ensure_dir(LogFile),
    [logger:remove_handler(H) || H <- logger:get_handler_ids()],
    Handler = #{
        config => #{
            file => LogFile, max_no_bytes => ?LOG_MAX_NO_BYTES, max_no_files => ?LOG_MAX_NO_FILES
        },
        level => ?LOG_LEVEL,
        formatter => {logger_formatter, #{template => ?LOG_FORMAT}}
    },
    StdErrHandler = #{
        config => #{type => standard_error},
        level => ?LOG_LEVEL,
        formatter => {logger_formatter, #{template => ?LOG_FORMAT}}
    },
    logger:add_handler(edb_core_handler, logger_std_h, Handler),
    logger:add_handler(edb_stderr_handler, logger_std_h, StdErrHandler),
    logger:set_primary_config(level, ?LOG_LEVEL),
    ok.
