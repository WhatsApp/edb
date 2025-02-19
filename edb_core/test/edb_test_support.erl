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

-module(edb_test_support).
-compile(warn_missing_spec_all).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).

-include_lib("stdlib/include/assert.hrl").
-include_lib("common_test/include/ct.hrl").

%% Peer nodes
-export_type([peer/0, start_peer_node_opts/0]).
-export([start_peer_node/2, stop_peer_node/1, stop_all_peer_nodes/0]).
-export([compile_and_load_file_in_peer/1]).
-export([random_node/1]).

%% Event collection
-export([start_event_collector/0, collected_events/0, stop_event_collector/0, event_collector_send_sync/0]).

%% --------------------------------------------------------------------
%% Peer nodes
%% --------------------------------------------------------------------

-define(PROC_DICT_PEERS_KEY, {?MODULE, peers}).

-type peer() :: gen_statem:ref().

-spec random_node(Prefix :: string() | binary()) -> node().
random_node(Prefix) ->
    Name = random_node_name(Prefix),
    Host = edb_node_monitor:safe_sname_hostname(),
    list_to_atom(io_lib:format("~s@~s", [Name, Host])).

-spec random_node_name(Prefix :: string() | binary()) -> atom().
random_node_name(Prefix) when is_binary(Prefix) ->
    random_node_name(binary_to_list(Prefix));
random_node_name(Prefix) ->
    list_to_atom(peer:random_name(Prefix)).

-type start_peer_node_opts() ::
    #{
        node => node() | {prefix, binary() | string()},
        cookie => atom(),
        copy_code_path => boolean(),
        enable_debugging_mode => boolean(),
        extra_args => [binary() | string()]
    }.

-spec start_peer_node(CtConfig, Opts) -> {ok, Peer, Node, Cookie} when
    CtConfig :: ct_suite:ct_config(),
    Opts :: start_peer_node_opts(),
    Peer :: peer(),
    Node :: node(),
    Cookie :: atom() | nocookie.
start_peer_node(CtConfig, Opts = #{node := Node}) when is_atom(Node) ->
    ok = ensure_distributed(),
    Cookie = maps:get(cookie, Opts, erlang:get_cookie()),
    ?assertNotEqual(Cookie, nocookie, "A cookie needs to be given if dist is not enabled"),
    [NodeName, NodeHost] = string:split(atom_to_list(Node), "@"),
    ExtraArgs0 = [
        case is_binary(Arg) of
            true -> binary_to_list(Arg);
            false -> Arg
        end
     || Arg <- maps:get(extra_args, Opts, [])
    ],
    ExtraArgs1 =
        case maps:get(enable_debugging_mode, Opts, true) of
            true -> ["+D" | ExtraArgs0];
            false -> ExtraArgs0
        end,
    {ok, Peer, Node} = ?CT_PEER(#{
        name => NodeName,
        host => NodeHost,
        % TCP port, 0 stands for "automatic selection"
        connection => 0,
        args => ["-connect_all", "false", "-setcookie", atom_to_list(Cookie)] ++ ExtraArgs1
    }),
    StartedPeers =
        case erlang:get(?PROC_DICT_PEERS_KEY) of
            undefined -> #{};
            Peers when is_map(Peers) -> Peers
        end,
    erlang:put(?PROC_DICT_PEERS_KEY, StartedPeers#{Peer => Node}),
    case maps:get(copy_code_path, Opts, false) of
        true ->
            ok = peer:call(Peer, code, add_pathsa, [code:get_path()]);
        false ->
            ok
    end,
    PrivDir = ?config(priv_dir, CtConfig),
    ok = peer:call(Peer, code, add_pathsa, [PrivDir]),
    {ok, Peer, Node, Cookie};
start_peer_node(CtConfig, Opts0) ->
    {NamePrefix, Opts2} =
        case maps:take(node, Opts0) of
            error -> {~"debuggee", Opts0};
            {{prefix, GivenPrefix}, Opts1} -> {GivenPrefix, Opts1}
        end,
    Node = random_node(NamePrefix),
    start_peer_node(CtConfig, Opts2#{node => Node}).

-spec stop_peer_node(Peer) -> ok when
    Peer :: peer().
stop_peer_node(Peer) ->
    try peer:stop(Peer) of
        ok ->
            ok
    catch
        exit:noproc ->
            ok
    end.

-spec stop_all_peer_nodes() -> ok.
stop_all_peer_nodes() ->
    case erlang:get(?PROC_DICT_PEERS_KEY) of
        undefined ->
            ok;
        Peers when is_map(Peers) ->
            [
                begin
                    % If the node is paused by edb, peer:stop() would silently timeout
                    % (init:stop() gets blocked, etc) so it will end up just "disconnecting"
                    % the peer node. The actual node keeps up, though, so we leak
                    % a OS process on each invocation of the test. So let's ensure the debugger
                    % is stopped (which resumes every process) to avoid leaking resources
                    catch erpc:call(Node, edb_server, stop, [], 30_000),
                    ok = stop_peer_node(Peer)
                end
             || Peer := Node <- Peers
            ],
            erlang:erase(?PROC_DICT_PEERS_KEY),
            ok
    end.

-spec compile_and_load_file_in_peer(#{source := File, peer := Peer, ebin => Ebin}) -> {ok, Module} when
    File :: file:name_all(),
    Ebin :: file:name_all(),
    Peer :: peer(),
    Module :: module().
compile_and_load_file_in_peer(Opts = #{source := File, peer := Peer}) ->
    CompileOpts = [debug_info, beam_debug_info],
    {module, Module1} =
        case maps:get(ebin, Opts, undefined) of
            undefined ->
                DummyBeamFile = filename:rootname(File, ".erl") ++ ".beam",
                {ok, Module, Bin} = compile:file(File, [binary | CompileOpts]),
                {module, Module} = peer:call(Peer, code, load_binary, [Module, DummyBeamFile, Bin]);
            EbinDir ->
                BeamFile = filename:join(EbinDir, filename:basename(File, ".erl")),
                {ok, Module} = compile:file(File, [{outdir, EbinDir} | CompileOpts]),
                {module, Module} = peer:call(Peer, code, load_abs, [BeamFile])
        end,
    {ok, Module1}.

%% ------------------------------------------------------------------
%% Event collector helpers
%% ------------------------------------------------------------------

-spec start_event_collector() -> ok.
start_event_collector() ->
    Caller = self(),
    Ref = erlang:make_ref(),
    Pid = erlang:spawn(fun() ->
        {ok, Subscription} = edb:subscribe(),
        Caller ! {sync, Ref},
        event_collector_loop(Subscription)
    end),
    erlang:register(edb_test_event_collector, Pid),
    receive
        {sync, Ref} -> ok
    after 10_000 -> error(timeout_staring_event_collector)
    end,
    ok.

-spec event_collector_loop(Subscription) -> ok when
    Subscription :: edb:event_subscription().
event_collector_loop(Subscription) ->
    receive
        {collect, Ref, From} ->
            {SyncRef, ReceiveTimeout} =
                try edb:send_sync_event(Subscription) of
                    {ok, SyncRef1} ->
                        {SyncRef1, 2_000};
                    {error, unknown_subscription} ->
                        % We must have been unsubscribed, similar to the not_attached case below
                        {erlang:make_ref(), 0}
                catch
                    error:not_attached ->
                        % We will not receive a sync ref anyway, so any ref will do.
                        % Use a 0ms timeout, since we know that `sync` event will never
                        % arrive
                        {erlang:make_ref(), 0}
                end,
            Go = fun Loop(Acc) ->
                receive
                    {edb_event, Subscription, {sync, SyncRef}} ->
                        lists:reverse(Acc);
                    {edb_event, Subscription, Event = {nodedown, _Node, _Reason}} ->
                        lists:reverse([Event | Acc]);
                    {edb_event, Subscription, Event} ->
                        Loop([Event | Acc])
                after ReceiveTimeout ->
                    case ReceiveTimeout of
                        0 -> lists:reverse(Acc);
                        _ -> error(timeout_collect_events)
                    end
                end
            end,
            From ! {Ref, Go([])},
            event_collector_loop(Subscription);
        {stop, Ref, From} ->
            From ! {Ref, ok},
            ok;
        {send_sync_event, Ref, From} ->
            {ok, SyncRef} = edb:send_sync_event(Subscription),
            From ! {Ref, SyncRef},
            event_collector_loop(Subscription)
    end.

-spec collected_events() -> [edb:event()].
collected_events() ->
    MonitorRef = erlang:monitor(process, edb_test_event_collector),
    Ref = erlang:make_ref(),
    edb_test_event_collector ! {collect, Ref, self()},
    receive
        {Ref, Events} ->
            Events;
        {'DOWN', MonitorRef, process, _, Reason} ->
            error({event_collector_crashed, Reason})
    after 2_000 ->
        error(timeout_collect_events)
    end.

-spec stop_event_collector() -> ok.
stop_event_collector() ->
    case erlang:whereis(edb_test_event_collector) of
        undefined ->
            ok;
        _ ->
            Ref = erlang:make_ref(),
            edb_test_event_collector ! {stop, Ref, self()},
            receive
                {Ref, ok} -> ok
            after 2_000 ->
                error(timeout_stop_event_collector)
            end
    end.

-spec event_collector_send_sync() -> {ok, SyncRef :: reference()}.
event_collector_send_sync() ->
    Me = self(),
    Ref = erlang:make_ref(),
    edb_test_event_collector ! {send_sync_event, Ref, Me},
    receive
        {Ref, SyncRef} -> {ok, SyncRef}
    after 2_000 -> error(timeout_sync_event_collector)
    end.

%% --------------------------------------------------------------------
%% Helpers
%% --------------------------------------------------------------------

-spec ensure_epmd() -> ok.
ensure_epmd() ->
    % epmd is started automatically only if `-name` nor `-sname` where
    % given as arguments
    (erl_epmd:names("localhost") =:= {error, address}) andalso
        ([] = os:cmd("epmd -daemon")),
    ok.

-spec ensure_distributed() -> ok.
ensure_distributed() ->
    case erlang:node() of
        'nonode@nohost' ->
            ensure_epmd(),
            Prefix = atom_to_list(?MODULE),
            Node = random_node(Prefix),
            {ok, _Pid} = net_kernel:start(Node, #{
                name_domain => shortnames,
                dist_listen => true,
                hidden => true
            }),
            ok;
        _ ->
            ok
    end.
