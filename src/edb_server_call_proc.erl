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
%% %%%---------------------------------------------------------------------------------
%% @doc Support for calling node processes that could be paused
%%
%% There are times were we want to call standard processed to query
%% node state. Typically these processes will be excluded from debugging
%% but if they are not, we want to make sure that the call fails, instead
%% of the debugger getting blocked
%% @end
%%%---------------------------------------------------------------------------------
%% % @format

-module(edb_server_call_proc).
-compile(warn_missing_spec_all).

%% erlfmt:ignore
% @fb-only: 
-compile(warn_missing_spec_all).

% Supported calls to standard services
-export([code_where_is_file/1]).

% Generic calls
-export([safe_send_recv/4]).

%%%---------------------------------------------------------------------------------
%%% Types
%%%---------------------------------------------------------------------------------
-export_type([result/1]).
-type result(A) ::
    {call_ok, A} | {call_error, noproc | suspended | timeout}.

%%%---------------------------------------------------------------------------------
%%% Supported calls to standard services
%%%---------------------------------------------------------------------------------
-spec code_where_is_file(Filename) -> result(non_existing | Absname) when
    Filename :: file:filename(),
    Absname :: file:filename().
code_where_is_file(Filename) ->
    TimeoutMs = 300,
    %% See code:where_is_file()
    code_server_call({where_is_file, Filename}, TimeoutMs).

-spec code_server_call(Request, TimeoutMs) -> result(Response) when
    Request :: term(),
    TimeoutMs :: pos_integer(),
    Response :: dynamic().
code_server_call(Request, TimeoutMs) ->
    %% See code_server:call()
    safe_send_recv(
        code_server,
        fun() ->
            {code_call, self(), Request}
        end,
        fun() ->
            receive
                {code_server, Response} -> Response
            end
        end,
        TimeoutMs
    ).

%%%---------------------------------------------------------------------------------
%%% Generic API
%%%---------------------------------------------------------------------------------

-spec safe_send_recv(Dest, Request, Receive, TimeoutMs) -> result(Res) when
    Dest :: atom(),
    Request :: fun(() -> Msg :: term()),
    Receive :: fun(() -> Res),
    TimeoutMs :: pos_integer().
safe_send_recv(Dest, Request, Receive, TimeoutMs) when is_atom(Dest), TimeoutMs > 0 ->
    case erlang:whereis(Dest) of
        undefined ->
            {call_error, noproc};
        DestPid when is_pid(DestPid) ->
            case erlang:process_info(DestPid, status) of
                {status, suspended} ->
                    {call_error, suspended};
                _ ->
                    Caller = erlang:self(),
                    Ref = erlang:make_ref(),
                    Pid = erlang:spawn(fun() ->
                        try
                            DestPid ! Request(),
                            Res = Receive(),
                            Caller ! {ok, Ref, Res}
                        catch
                            Class:Reason:ST ->
                                Caller ! {raise, Ref, Class, Reason, ST}
                        end
                    end),
                    Monitor = erlang:monitor(process, Pid),
                    receive
                        {ok, Ref, Res} ->
                            {call_ok, Res};
                        {raise, Ref, Class, Reason, ST} ->
                            erlang:raise(Class, Reason, ST)
                    after TimeoutMs ->
                        erlang:exit(Pid, kill),

                        % Ensure that if we received a late response from Pid, it gets
                        % removed from the message queue, to avoid leaks.
                        receive
                            {'DOWN', Monitor, process, Pid, _} -> ok
                        end,
                        receive
                            {ok, Ref, Res} ->
                                {call_ok, Res};
                            {raise, Ref, Class, Reason, ST} ->
                                erlang:raise(Class, Reason, ST)
                        after 0 ->
                            {call_error, timeout}
                        end
                    end
            end;
        _ ->
            {call_error, noproc}
    end.
