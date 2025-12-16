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

%% erlfmt:ignore
% @fb-only: -oncall("whatsapp_server_devx").
-compile(warn_missing_spec_all).
-typing([eqwalizer]).

-include_lib("common_test/include/ct.hrl").

%% Compiling test modues
-export_type([module_spec/0, compile_opts/0]).
-export([compile_modules/3, compile_module/3]).

%% Peer nodes
-export_type([peer/0, start_peer_node_opts/0, start_peer_result/0]).
-export_type([start_peer_no_dist_opts/0, start_peer_no_dist_result/0]).
-export([start_peer_node/2, start_peer_no_dist/2, stop_peer/1, stop_all_peers/0]).
-export([random_node/1, random_node/2]).
-export([random_srcdir/1]).

%% Event collection
-export([start_event_collector/0, collected_events/0, stop_event_collector/0, event_collector_send_sync/0]).

%% Conversions
-export([file_name_all_to_string/1, file_name_all_to_binary/1, safe_string_to_binary/1]).

%% Debugger node utils
-export([start_debugger_node/1, on_debugger_node/2]).

%% --------------------------------------------------------------------
%% Compiling test modules
%% --------------------------------------------------------------------
-type module_spec() :: {filename, file:name_all()} | {filepath, file:filename_all()} | {source, iodata()}.
-type compile_opts() :: #{
    work_dir => file:filename_all(),
    load_it => boolean(),
    flags => [compile:option()]
}.
-type compile_opts_full() :: #{
    work_dir := file:filename_all(),
    load_it := boolean(),
    flags := [compile:option()]
}.

-spec compile_modules(CtConfig, ModuleSpecs, Opts) -> {ok, #{Module => FilePath}} when
    CtConfig :: ct_suite:ct_config(),
    ModuleSpecs :: [module_spec()],
    Opts :: compile_opts(),
    Module :: module(),
    FilePath :: binary().
compile_modules(CtConfig, ModuleSpecs, Opts0) ->
    {ok,
        #{
            Module => FilePath
         || ModuleSpec <- ModuleSpecs,
            {ok, Module, FilePath} <- [compile_module(CtConfig, ModuleSpec, Opts0)]
        }}.

-spec compile_module(CtConfig, ModuleSpec, Opts) -> {ok, Module, FilePath} when
    CtConfig :: ct_suite:ct_config(),
    ModuleSpec :: module_spec(),
    Opts :: compile_opts(),
    Module :: module(),
    FilePath :: binary().
compile_module(CtConfig, ModuleSpec, Opts0) ->
    Opts1 =
        case Opts0 of
            #{work_dir := _} ->
                Opts0;
            _ ->
                WorkDir = proplists:get_value(priv_dir, CtConfig),
                Opts0#{work_dir => WorkDir}
        end,
    Opts2 =
        case Opts1 of
            #{load_it := _} -> Opts1;
            _ -> Opts1#{load_it => false}
        end,
    Opts3 =
        case Opts2 of
            #{flags := _} ->
                Opts2;
            _ ->
                DefaultFlags = [debug_info, beam_debug_info],
                Opts2#{flags => DefaultFlags}
        end,
    compile_module_1(CtConfig, ModuleSpec, Opts3).

-spec compile_module_1(CtConfig, ModuleSpec, Opts) -> {ok, Module, FilePath} when
    CtConfig :: ct_suite:ct_config(),
    ModuleSpec :: module_spec(),
    Opts :: compile_opts_full(),
    Module :: module(),
    FilePath :: binary().
compile_module_1(_CtConfig, {filepath, FilePath}, Opts) ->
    compile_module_2(FilePath, Opts);
compile_module_1(CtConfig, {filename, FileName}, Opts) ->
    DataDir = ?config(data_dir, CtConfig),
    FilePath = filename:join(DataDir, FileName),
    {ok, Contents} = file:read_file(FilePath),
    compile_module_1(CtConfig, {source, Contents}, Opts);
compile_module_1(CtConfig, {source, Source}, Opts) ->
    #{work_dir := WorkDir} = Opts,
    MatchModuleRegex = ~"-module\\(([^)]+)\\)\\.",
    case re:run(Source, MatchModuleRegex, [{capture, all_but_first, list}]) of
        {match, [ModuleName]} ->
            FilePath = filename:join([WorkDir, "src", ModuleName ++ ".erl"]),
            ok = filelib:ensure_dir(FilePath),
            ok = file:write_file(FilePath, Source),
            compile_module_1(CtConfig, {filepath, FilePath}, Opts);
        nomatch ->
            error(couldnt_parse_module_name)
    end.

-spec compile_module_2(SourceFile, Opts) -> {ok, Module, FilePath} when
    SourceFile :: file:filename_all(),
    Opts :: compile_opts_full(),
    Module :: module(),
    FilePath :: binary().
compile_module_2(SourceFile, Opts) ->
    CompileOpts = maps:get(flags, Opts),
    WorkDir = maps:get(work_dir, Opts),
    FilePathStr = file_name_all_to_string(SourceFile),
    Ebindir = filename:join(WorkDir, "ebin"),
    ok = filelib:ensure_path(Ebindir),
    ModuleName = filename:basename(FilePathStr, ".erl"),
    case compile:file(FilePathStr, [{outdir, Ebindir}, return_errors | CompileOpts]) of
        {ok, Module} ->
            case Opts of
                #{load_it := true} ->
                    BeamFilePath = filename:join(Ebindir, ModuleName),
                    {module, Module} = code:load_abs(BeamFilePath);
                _ ->
                    ok
            end,
            {ok, Module, safe_string_to_binary(FilePathStr)};
        {error, [{_, Errors} | _], _Warns} ->
            error({compile_error, ModuleName, Errors})
    end.

%% --------------------------------------------------------------------
%% Peer nodes
%% --------------------------------------------------------------------

-define(PROC_DICT_PEERS_KEY, {?MODULE, peers}).

-type peer() :: peer:server_ref().

-spec random_node(Prefix) -> node() when
    Prefix :: string() | binary().
random_node(Prefix) ->
    random_node(Prefix, shortnames).

-spec random_node(Prefix, NameDomain) -> node() when
    Prefix :: string() | binary(),
    NameDomain :: shortnames | longnames.
random_node(Prefix, NameDomain) ->
    Name = random_node_name(Prefix),
    Host =
        case NameDomain of
            shortnames ->
                edb_node_monitor:safe_sname_hostname();
            longnames ->
                {ok, FQDN} = net:gethostname(),
                FQDN
        end,
    list_to_atom(lists:flatten(io_lib:format("~s@~s", [Name, Host]))).

-spec random_node_name(Prefix :: string() | binary()) -> atom().
random_node_name(Prefix) when is_binary(Prefix) ->
    random_node_name(binary_to_list(Prefix));
random_node_name(Prefix) ->
    list_to_atom(peer:random_name(Prefix)).

-spec random_srcdir(CtConfig) -> Dir when
    CtConfig :: ct_suite:ct_config(),
    Dir :: binary().
random_srcdir(CtConfig) ->
    PrivDir = ?config(priv_dir, CtConfig),
    UniqName = lists:concat([os:getpid(), "-", erlang:unique_integer([positive])]),
    WorkDir = filename:join(PrivDir, UniqName),
    SrcDir = filename:join(WorkDir, "src"),
    ok = file:make_dir(WorkDir),
    ok = file:make_dir(SrcDir),
    file_name_all_to_binary(SrcDir).

-type start_peer_node_opts() ::
    #{
        node => undefined | node() | {prefix, binary() | string()},
        cookie => atom(),
        copy_code_path => boolean(),
        enable_debugging_mode => boolean(),
        env => #{binary() => binary()},
        extra_args => [binary() | string()],
        srcdir => binary(),
        modules => [module_spec()],
        compile_flags => [compile:option()]
    }.

-type start_peer_result() :: #{
    peer := peer(),
    node := node(),
    cookie := atom(),
    srcdir => binary(),
    modules := #{module() => FilePath :: binary()}
}.

-type start_peer_no_dist_opts() ::
    #{
        copy_code_path => boolean(),
        enable_debugging_mode => boolean(),
        env => #{binary() => binary()},
        extra_args => [binary() | string()],
        srcdir => binary(),
        modules => [module_spec()],
        compile_flags => [compile:option()]
    }.

-type start_peer_no_dist_result() :: #{
    peer := peer(),
    srcdir := binary(),
    modules := #{module() => FilePath :: binary()}
}.

-spec start_peer_node(CtConfig, Opts) -> {ok, Result} when
    CtConfig :: ct_suite:ct_config(),
    Opts :: start_peer_node_opts(),
    Result :: start_peer_result().
start_peer_node(CtConfig, Opts = #{node := Node}) when is_atom(Node) ->
    Cookie =
        case Opts of
            #{cookie := C} ->
                C;
            _ ->
                case erlang:get_cookie() of
                    nocookie ->
                        list_to_atom(integer_to_list(erlang:unique_integer([positive])));
                    DefaultCookie ->
                        DefaultCookie
                end
        end,
    {ok, Peer, Srcdir, Modules} = gen_start_peer(
        CtConfig, #{node => Node, cookie => Cookie}, maps:without([node, cookie], Opts)
    ),
    {ok, #{peer => Peer, node => Node, cookie => Cookie, srcdir => Srcdir, modules => Modules}};
start_peer_node(CtConfig, Opts0) ->
    {NamePrefix, Opts2} =
        case maps:take(node, Opts0) of
            error -> {~"debuggee", Opts0};
            {{prefix, GivenPrefix}, Opts1} -> {GivenPrefix, Opts1}
        end,
    Node = random_node(NamePrefix),
    start_peer_node(CtConfig, Opts2#{node => Node}).

-spec start_peer_no_dist(CtConfig, Opts) -> {ok, Result} when
    CtConfig :: ct_suite:ct_config(),
    Opts :: start_peer_no_dist_opts(),
    Result :: start_peer_no_dist_result().
start_peer_no_dist(CtConfig, Opts) ->
    {ok, Peer, Workdir, Modules} = gen_start_peer(CtConfig, no_dist, Opts),
    % Sanity-check
    #{started := no} = peer:call(Peer, net_kernel, get_state, []),
    {ok, #{peer => Peer, srcdir => Workdir, modules => Modules}}.

-spec gen_start_peer(CtConfig, NodeInfo, Opts) -> {ok, Peer, SrcDir, Modules} when
    CtConfig :: ct_suite:ct_config(),
    NodeInfo :: no_dist | #{node := node(), cookie := atom()},
    Opts :: start_peer_no_dist_opts(),
    Peer :: peer(),
    SrcDir :: binary(),
    FilePath :: binary(),
    Modules :: #{module() => FilePath}.
gen_start_peer(CtConfig, NodeInfo, Opts) ->
    CommonArgs = ["-connect_all", "false", "+S2", "+Q65535"],
    CookieArgs =
        case NodeInfo of
            no_dist -> [];
            #{cookie := C} -> ["-setcookie", atom_to_list(C)]
        end,
    DebuggingArgs =
        case maps:get(enable_debugging_mode, Opts, true) of
            true -> ["+D"];
            false -> []
        end,
    ExtraArgs = [
        case Arg of
            BinArg when is_binary(BinArg) -> binary_to_list(BinArg);
            StrArg -> StrArg
        end
     || Arg <- maps:get(extra_args, Opts, [])
    ],
    PeerOpts0 = #{
        % TCP port, 0 stands for "automatic selection"
        connection => 0,

        % The control process stays up when the connection is lost,
        % so we can query the node state, etc
        peer_down => continue,
        args => [Arg || Args <- [CommonArgs, CookieArgs, DebuggingArgs, ExtraArgs], Arg <- Args],
        env => [{binary_to_list(K), binary_to_list(V)} || K := V <- maps:get(env, Opts, #{})]
    },
    PeerOpts1 =
        case NodeInfo of
            no_dist ->
                PeerOpts0;
            #{node := undefined} ->
                PeerOpts0#{name => undefined};
            #{node := Node} ->
                [NodeName, NodeHost] = string:split(atom_to_list(Node), "@"),
                PeerOpts0#{
                    name => NodeName,
                    host => NodeHost
                }
        end,
    {ok, Peer, _Node} = ?CT_PEER(PeerOpts1),

    case NodeInfo of
        no_dist ->
            % ?CT_PEER() always gives the node a name, so it starts distribution. So let's
            % manually kill the net supervisor
            ok = peer:call(Peer, supervisor, terminate_child, [kernel_sup, net_sup]),
            ok = peer:call(Peer, supervisor, delete_child, [kernel_sup, net_sup]);
        _ ->
            ok
    end,

    StartedPeers =
        case erlang:get(?PROC_DICT_PEERS_KEY) of
            undefined -> #{};
            Peers when is_map(Peers) -> Peers
        end,
    erlang:put(?PROC_DICT_PEERS_KEY, StartedPeers#{Peer => NodeInfo}),
    case maps:get(copy_code_path, Opts, false) of
        true ->
            ok = peer:call(Peer, code, add_pathsa, [code:get_path()]);
        false ->
            ok
    end,
    SrcDir =
        case Opts of
            #{srcdir := GivenSrcDir} ->
                GivenSrcDir;
            _ ->
                random_srcdir(CtConfig)
        end,
    WorkDir = file_name_all_to_string(filename:dirname(SrcDir)),
    EbinDir = filename:join(WorkDir, "ebin"),
    ok = file:make_dir(EbinDir),
    true = peer:call(Peer, code, add_patha, [EbinDir]),

    CompileOpts0 = #{work_dir => WorkDir},
    CompileOpts1 =
        case Opts of
            #{compile_flags := Flags} ->
                CompileOpts0#{flags => Flags};
            _ ->
                CompileOpts0
        end,
    Modules =
        #{
            Module => BeamFilePath
         || ModuleSpec <- maps:get(modules, Opts, []),
            {ok, Module, BeamFilePath} <- [compile_module(CtConfig, ModuleSpec, CompileOpts1)]
        },

    {ok, Peer, SrcDir, Modules}.

-spec stop_peer(Peer) -> ok when
    Peer :: peer().
stop_peer(Peer) ->
    try peer:stop(Peer) of
        ok ->
            ok
    catch
        exit:noproc ->
            ok
    end.

-spec stop_all_peers() -> ok.
stop_all_peers() ->
    case erlang:get(?PROC_DICT_PEERS_KEY) of
        undefined ->
            ok;
        Peers when is_map(Peers) ->
            [
                begin
                    case NodeInfo of
                        no_dist ->
                            ok;
                        #{node := Node} ->
                            % If the node is paused by edb, peer:stop() would silently timeout
                            % (init:stop() gets blocked, etc) so it will end up just "disconnecting"
                            % the peer node. The actual node keeps up, though, so we leak
                            % a OS process on each invocation of the test. So let's ensure the debugger
                            % is stopped (which resumes every process) to avoid leaking resources
                            try
                                erpc:call(Node, edb_server, stop, [], 30_000)
                            catch
                                _:_ -> ok
                            end
                    end,
                    ok = stop_peer(Peer)
                end
             || Peer := NodeInfo <- Peers
            ],
            erlang:erase(?PROC_DICT_PEERS_KEY),
            ok
    end.

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

%% -------------------------------------------------------------------
%% Conversions
%% -------------------------------------------------------------------
-spec file_name_all_to_string(file:name_all()) -> string().
file_name_all_to_string(FileNameAll) ->
    case filename:flatten(FileNameAll) of
        Bin when is_binary(Bin) -> binary_to_list(Bin);
        Str -> Str
    end.

-spec file_name_all_to_binary(file:name_all()) -> binary().
file_name_all_to_binary(FileNameAll) ->
    case filename:flatten(FileNameAll) of
        Bin when is_binary(Bin) -> Bin;
        Str -> safe_string_to_binary(Str)
    end.

-spec safe_string_to_binary(string()) -> binary().
safe_string_to_binary(String) ->
    case unicode:characters_to_binary(String) of
        Bin when is_binary(Bin) -> Bin
    end.

%% -------------------------------------------------------------------
%% Debugger node utils
%% -------------------------------------------------------------------
-spec start_debugger_node(Config) -> Config when
    Config :: ct_suite:ct_config().
start_debugger_node(Config0) ->
    {ok, #{peer := Peer}} = start_peer_no_dist(Config0, #{
        copy_code_path => true
    }),
    Config1 = [{debugger_peer_key(), Peer} | Config0],
    {ok, _} = on_debugger_node(Config1, fun() ->
        application:ensure_all_started(edb_core)
    end),
    Config1.

-spec on_debugger_node(Config, fun(() -> Result)) -> Result when
    Config :: ct_suite:ct_config().
on_debugger_node(Config, Fun) ->
    Peer = ?config(debugger_peer_key(), Config),
    peer:call(Peer, erlang, apply, [Fun, []], infinity).

-spec debugger_peer_key() -> debugger_peer.
debugger_peer_key() -> debugger_peer.
