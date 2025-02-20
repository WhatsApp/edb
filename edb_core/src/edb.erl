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
%% @doc The (new!) Erlang debugger
-module(edb).

%% erlfmt:ignore
% @fb-only
-compile(warn_missing_spec_all).
-compile({no_auto_import, [processes/0]}).

%% External exports
-export([attach/1, detach/0, terminate/0]).
-export([attached_node/0]).

-export([subscribe/0, unsubscribe/1, send_sync_event/1]).

-export([pause/0, continue/0, wait/0]).

-export([add_breakpoint/2]).
-export([clear_breakpoint/2, clear_breakpoints/1]).
-export([set_breakpoints/2]).
-export([get_breakpoints/0, get_breakpoints/1]).
-export([get_breakpoints_hit/0]).

-export([step_over/1, step_out/1]).

-export([processes/0, process_info/1]).

-export([is_paused/0]).

-export([excluded_processes/0, exclude_process/1, exclude_processes/1, unexclude_processes/1]).

-export([stack_frames/1, stack_frame_vars/2, stack_frame_vars/3]).

-export([format/2]).

%% -------------------------------------------------------------------
%% Types
%% -------------------------------------------------------------------
-type line() :: pos_integer().
-export_type([line/0]).

-type fun_name() :: atom().
-export_type([fun_name/0]).

-export_type([bootstrap_failure/0]).
-type bootstrap_failure() ::
    {no_debugger_support, {missing, erl_debugger} | not_enabled}
    | {module_injection_failed, module(), Reason :: term()}.

-export_type([breakpoint_info/0]).
-type breakpoint_info() :: #{
    module := module(),
    line := line()
}.

-export_type([add_breakpoint_error/0]).
-type add_breakpoint_error() ::
    unsupported
    | {unsupported, module()}
    | {unsupported, Line :: line()}
    | {badkey, module()}
    | {badkey, Line :: line()}.

-export_type([set_breakpoints_result/0]).
-type set_breakpoints_result() :: [{line(), Result :: ok | {error, add_breakpoint_error()}}].

-type step_error() ::
    no_abstract_code
    | not_paused
    | {beam_analysis, term()}.

-export_type([step_over_error/0]).
-type step_over_error() :: step_error().

-export_type([step_out_error/0]).
-type step_out_error() :: step_error().

-export_type([procs_spec/0]).
-type procs_spec() :: {proc, pid() | atom()} | {application, atom()} | {except, pid()}.

-export_type([process_info/0, process_status/0]).
-type process_info() :: #{
    status := process_status(),
    application => atom(),
    current_fun => mfa(),
    current_loc => {string(), line()},
    current_bp => {line, line()},
    parent => atom() | pid(),
    registered_name => atom(),
    message_queue_len => non_neg_integer()
}.

-type process_status() ::
    running | paused | breakpoint.

-export_type([excluded_process_info/0, exclusion_reason/0]).
-type excluded_process_info() :: #{
    application => atom(),
    current_fun => mfa(),
    current_loc => {string(), line()},
    parent => atom() | pid(),
    reason => [exclusion_reason()],
    registered_name => atom(),
    message_queue_len => non_neg_integer()
}.

-type exclusion_reason() ::
    debugger_component
    | excluded_application
    | excluded_pid
    | excluded_regname
    | system_component.

-export_type([frame_id/0, stack_frame/0, stack_frame_vars/0, value/0, catch_handler/0]).
-type frame_id() :: non_neg_integer().
-type stack_frame() :: #{
    id := frame_id(),
    mfa := mfa() | unknown,
    source := file:filename() | undefined,
    line := line() | undefined
}.
-type stack_frame_vars() :: #{
    vars => #{binary() => value()},
    xregs => [value()],
    yregs => [value()]
}.
-type value() :: {value, term()} | {too_large, Size :: pos_integer(), Max :: pos_integer()}.
-type catch_handler() :: {'catch', {mfa(), {line, line() | undefined}}}.

-export_type([event_envelope/1, event_subscription/0]).
-export_type([event/0, resumed_event/0, paused_event/0]).
-type event_envelope(Event) :: {edb_event, event_subscription(), Event}.
-type event_subscription() :: edb_events:subscription().
-type event() ::
    {resumed, resumed_event()}
    | {paused, paused_event()}
    | {sync, reference()}
    | {terminated, Reason :: term()}
    | unsubscribed
    | {nodedown, node(), Reason :: term()}.
-type resumed_event() ::
    {continue, all}
    | {excluded, #{pid() => []}}
    | {termination, all}.
-type paused_event() ::
    {breakpoint, pid(), mfa(), {line, line()}}
    | pause
    | {step, pid()}.

%% -------------------------------------------------------------------
%% External exports
%% -------------------------------------------------------------------

%% @doc Start a debugging session by attaching to the given node.
%%
%% If edb was already attached to a node, it will get detached first.
%% The attached node may already have a debugging session in progress,
%% in this case, edb joins it.
%%
%% This call may start distribution and set the node name.
%%
%% Arguments:
%%
%% * `node' - the node to attach to
%% * `timeout' - how long to wait for the node to be up; defaults to 0,
%% * 'cookie' - cookie to use for connecting to the node
-spec attach(#{
    node := node(),
    timeout => timeout(),
    cookie => atom()
}) -> ok | {error, Reason} when
    Reason ::
        attachment_in_progress
        | nodedown
        | bootstrap_failure().
attach(AttachOpts0) ->
    {NodeToDebug, AttachOpts1} = take_arg(node, AttachOpts0, #{parse => fun parse_atom/1}),
    {AttachTimeout, AttachOpts2} = take_arg(timeout, AttachOpts1, #{default => 0, parse => fun parse_timeout/1}),
    {Cookie, AttachOpts3} = take_arg(cookie, AttachOpts2, #{default => {default}, parse => fun parse_atom/1}),
    ok = no_more_args(AttachOpts3),

    case NodeToDebug of
        nonode@nohost when NodeToDebug /= node() ->
            error({invalid_node, NodeToDebug});
        nonode@nohost ->
            ok;
        _ ->
            NameDomain = infer_name_domain(NodeToDebug),
            ok = maybe_start_distribution(NameDomain)
    end,

    case Cookie of
        {default} -> ok;
        _ -> true = erlang:set_cookie(NodeToDebug, Cookie)
    end,

    edb_node_monitor:attach(NodeToDebug, AttachTimeout).

%% @doc Detach from the currently attached node.
%%
%% The debugger session running on the node is left undisturbed.
-spec detach() -> ok.
detach() ->
    edb_node_monitor:detach().

%% @doc Terminates the debugging session.
%%
%% Detaches from the node, but stopping the debugger running on it.
%% That means that breakpoints will be cleared, and any paused processes
%% will be resumed, etc.
-spec terminate() -> ok.
terminate() ->
    ok = rpc_attached_node(edb_server, stop, []),
    ok = edb_node_monitor:detach(),
    ok.

%% @doc Returns the node being debugged.
%%
%% Will raise a `not_attached' error if not attached.
-spec attached_node() -> node().
attached_node() ->
    edb_node_monitor:attached_node().

%% @doc Subscribe caller process to receive debugging events from the attached node.
%%
%% The caller process can then expect messages of type `event_envelope(event())', with
%% the specified subscription in the envelope.
%% A process can  hold multiple subscriptions and can unsubscribe from them individually.
-spec subscribe() -> {ok, event_subscription()}.
subscribe() ->
    edb_node_monitor:subscribe().

%% @doc Remove a previously added subscription.
%%
%% The caller process need not be the one holding the subscription. An `unsubscribed' event
%% will be sent as final event to the subscription, which marks the end of the event stream.
-spec unsubscribe(Subscription) -> ok when
    Subscription :: event_subscription().
unsubscribe(Subscription) ->
    edb_node_monitor:unsubscribe(Subscription).

%% @doc Request that a `sync' event is sent to the given subscription.
%%
%% The process holding the subscription will receive a `sync' event,
%% with the returned reference as value. This can be used to ensure that
%% there are no events the server is planning to send.
%%
%% Returns `{error, unknown_subscription}' if the subscription is not known.
-spec send_sync_event(Subscription) -> {ok, SyncRef} | undefined when
    Subscription :: event_subscription(),
    SyncRef :: reference().
send_sync_event(Subscription) ->
    call_server({send_sync_event, Subscription}).

%% @doc Set a breakpoint on the line of a loaded module on the remote node.
-spec add_breakpoint(Module, Line) -> ok | {error, Reason} when
    Module :: module(),
    Line :: line(),
    Reason :: edb:add_breakpoint_error().
add_breakpoint(Module, Line) ->
    call_server({add_breakpoint, Module, Line}).

%% @doc Clear all previously set breakpoints of a module on the remote node.
-spec clear_breakpoints(Module) -> ok when
    Module :: module().
clear_breakpoints(Module) ->
    call_server({clear_breakpoints, Module}).

%% @doc Clear a previously set breakpoint on the remote node.
-spec clear_breakpoint(Module, Line) -> ok | {error, not_found} when
    Module :: module(),
    Line :: line().
clear_breakpoint(Module, Line) ->
    call_server({clear_breakpoint, Module, Line}).

%% @doc Set breakpoints for a given module on the remote node.
-spec set_breakpoints(Module, [Line]) -> Result when
    Module :: module(),
    Line :: line(),
    Result :: set_breakpoints_result().
set_breakpoints(Module, Lines) ->
    call_server({set_breakpoints, Module, Lines}).

%% @doc Get all currently set breakpoints on the remote node.
-spec get_breakpoints() -> #{module() => [breakpoint_info()]}.
get_breakpoints() ->
    call_server(get_breakpoints).

%% @doc Get currently set breakpoints for a given module on the remote node.
-spec get_breakpoints(Module) -> [breakpoint_info()] when
    Module :: module().
get_breakpoints(Module) ->
    call_server({get_breakpoints, Module}).

%% @doc Pause the execution of the remote node.
-spec pause() -> ok.
pause() ->
    call_server(pause).

%% @doc Continues the execution on the remote node and returns right away.
%%
%% Returns `not_paused' if no process was paused, otherwise `resumed'.
-spec continue() -> {ok, resumed | not_paused}.
continue() ->
    call_server(continue).

-spec step_over(pid()) -> ok | {error, step_over_error()}.
step_over(Pid) ->
    call_server({step_over, Pid}).

-spec step_out(pid()) -> ok | {error, step_out_error()}.
step_out(Pid) ->
    call_server({step_out, Pid}).

%% @doc Waits until the node gets paused.
-spec wait() -> {ok, paused}.
wait() ->
    {ok, Subscription} = subscribe(),
    case is_paused() of
        true ->
            % Already paused, so we can return immediately
            ok;
        false ->
            % Wait for a process to be paused
            receive
                {edb_event, Subscription, {paused, _}} -> ok
            end
    end,
    release_subscription(Subscription),
    {ok, paused}.

%% @doc Get the list of processes currently paused at a breakpoint on the remote node.
-spec get_breakpoints_hit() -> #{pid() => breakpoint_info()}.
get_breakpoints_hit() ->
    call_server(get_breakpoints_hit).

%% @doc Get information about a process managed by the debugger on the remote node.
-spec process_info(pid()) -> {ok, process_info()} | undefined.
process_info(Pid) ->
    call_server({process_info, Pid}).

%% @doc Get the set of processes managed by the debugger on the remote node.
-spec processes() -> #{pid() => process_info()}.
processes() ->
    call_server(processes).

%% @doc List the pids that will not be paused by the debugger on the remote node.
-spec excluded_processes() -> #{pid() => []}.
excluded_processes() ->
    call_server(excluded_processes).

%% @doc Check if there exists paused processes.
-spec is_paused() -> boolean().
is_paused() ->
    call_server(is_paused).

%% @doc
%% Add a single process to the set of processes excluded from debugging.
%% It is equivalent to `exclude_processes([{proc, Proc}])'.
-spec exclude_process(Proc) -> ok when
    Proc :: pid() | atom().
exclude_process(Proc) ->
    exclude_processes([{proc, Proc}]).

%% @doc
%%
%% Extend the set of processes excluded by the debugger.
%%
%% Processes can be specified in the following ways:
%%     - by pid,
%%     - by being part of an application,
%%     - exception list for pids that should not be excluded
%%
%% E.g. a spec like:
%% ```
%% [Pid1, {appication, foo}, {application, bar}, {except, Pid2}, {except, Pid3}]
%% '''
%% will exclude `Pid1' and all processes in applications `foo' and `bar'; however
%% `Pid2' and `Pid3' are guaranteed not to be excluded, whether they are part
%% of `foo', `bar', etc. The order of the spec clauses is irrelevant and, in
%% particular, `except' clauses are global.
%%
%% If any specified processes are currently paused, they will
%% be automatically resumed.
-spec exclude_processes(Specs) -> ok when
    Specs :: [procs_spec()].
exclude_processes(Specs) ->
    validate_procs_spec(Specs),
    call_server({exclude_processes, Specs}).

%% @doc
%%
%% Removes an exclusion previously added with `exclude_processes/1'.
%%
%% If there are currently paused processes, any specified processes
%% will be paused as well.
-spec unexclude_processes(Specs) -> ok when
    Specs :: [procs_spec()].
unexclude_processes(Specs) ->
    validate_procs_spec(Specs),
    call_server({unexclude_processes, Specs}).

%% @doc
%% Get the stack frames for a paused process.
%%
%% The `FrameNo' can then be used to retrieve the variables for
%% a particular frame.
-spec stack_frames(Pid) -> not_paused | {ok, [Frame]} when
    Pid :: pid(),
    Frame :: stack_frame().
stack_frames(Pid) ->
    call_server({stack_frames, Pid}).

%% @doc Get the local variables for a paused processes at a give frame.
%%
%% Equivalent to `stack_frame_vars(Pid, 2048)'.
-spec stack_frame_vars(Pid, FrameId) -> not_paused | undefined | {ok, Result} when
    Pid :: pid(),
    FrameId :: frame_id(),
    Result :: stack_frame_vars().
stack_frame_vars(Pid, FrameId) ->
    DefaultMaxTermSize = 2048,
    stack_frame_vars(Pid, FrameId, DefaultMaxTermSize).

%% @doc
%% Get the local variables for a paused process at a given frame.
%%
%% The value of `FrameId` must be one of the frame-ids returned
%% by `stack_frames/1', or the call will return `undefined'.
%%
%% For each variable, the value is returned only if its internal
%% size is at most `MaxTermSize', otherwise `{too_large, Size, MaxTermSize}'
%% is returned. This is to prevent the caller from getting
%% objects that are larger than they are willing to handle.
-spec stack_frame_vars(Pid, FrameId, MaxTermSize) ->
    not_paused | undefined | {ok, Result}
when
    Pid :: pid(),
    FrameId :: frame_id(),
    MaxTermSize :: pos_integer(),
    Result :: stack_frame_vars().
stack_frame_vars(Pid, FrameId, MaxTermSize) ->
    call_server({stack_frame_vars, Pid, FrameId, MaxTermSize}).

%% doc
%% Run `io_lib:format(Format, Args)' on the remote node.
%%
%% This is useful to get a human-readable representation of terms
%% where Pids, Refs, etc. are displayed relative to the node being
%% debugged.
-spec format(Format, Args) -> binary() when
    Format :: io:format(),
    Args :: [term()].
format(Format, Args) when is_list(Args) ->
    % elp:ignore W0014 (cross_node_eval) - Debugging tool, expected.
    case rpc_attached_node(io_lib, format, [Format, Args]) of
        Chars when is_list(Chars) ->
            String = lists:flatten(Chars),
            case unicode:characters_to_binary(String) of
                Binary when is_binary(Binary) -> Binary
            end
    end.

%% -------------------------------------------------------------------
%% Helpers
%% -------------------------------------------------------------------

-spec call_server(Request :: edb_server:call_request()) -> dynamic().
call_server(Request) ->
    Node = attached_node(),
    try
        edb_server:call(Node, Request)
    catch
        exit:{{nodedown, Node}, {gen_server, call, Args}} when is_list(Args) ->
            edb_node_monitor:detach(),
            error(not_attached)
    end.

-spec rpc_attached_node(M, F, Args) -> dynamic() when
    M :: module(),
    F :: atom(),
    Args :: [term()].
rpc_attached_node(M, F, Args) ->
    try
        % elp:ignore W0014 (cross_node_eval) - Debugging tool, expected.
        erpc:call(attached_node(), M, F, Args)
    catch
        error:{erpc, noconnection} ->
            edb_node_monitor:detach(),
            error(not_attached)
    end.

-spec release_subscription(event_subscription()) -> ok.
release_subscription(Subscription) ->
    ok = unsubscribe(Subscription),
    Go = fun Loop() ->
        receive
            {edb_event, Subscription, unsubscribed} -> ok;
            {edb_event, Subscription, _} -> Loop()
        end
    end,
    Go().

%% -------------------------------------------------------------------
%% Distribution
%% -------------------------------------------------------------------
-spec maybe_start_epmd() -> ok.
maybe_start_epmd() ->
    case init:get_argument(start_epmd) of
        {ok, [["false"]]} ->
            % we were told not to start epmd, hopefully the user knows what they are doing
            ok;
        _ ->
            case erl_epmd:names("localhost") of
                {error, address} ->
                    % not running, let's start it ourselves
                    EpmdPath = filename:join([code:root_dir(), "bin", "epmd"]),
                    Cmd = lists:flatten(io_lib:format("~s -daemon", [EpmdPath])),
                    [] = os:cmd(Cmd),
                    ok;
                _ ->
                    ok
            end
    end.

-spec debugger_node(NameDomain) -> node() when
    NameDomain :: longnames | shortnames.
debugger_node(NameDomain) ->
    Host =
        case NameDomain of
            longnames ->
                {ok, FQHostname} = net:gethostname(),
                FQHostname;
            shortnames ->
                edb_node_monitor:safe_sname_hostname()
        end,
    NodeName = lists:flatten(
        io_lib:format("edb-~s-~p@~s", [
            os:getpid(),
            erlang:unique_integer([positive]),
            Host
        ])
    ),
    list_to_atom(NodeName).

-spec maybe_start_distribution(NameDomain) -> ok when
    NameDomain :: longnames | shortnames.
maybe_start_distribution(NameDomain) ->
    case erlang:node() of
        'nonode@nohost' ->
            maybe_start_epmd(),
            Node = debugger_node(NameDomain),
            {ok, _Pid} = net_kernel:start(Node, #{
                name_domain => NameDomain,
                dist_listen => true,
                hidden => true
            }),
            ok;
        _ ->
            ok
    end.

-spec infer_name_domain(Node) -> NameDomain when
    Node :: node(),
    NameDomain :: longnames | shortnames.
infer_name_domain(Node) ->
    case string:split(atom_to_list(Node), "@") of
        [_Name, Host] ->
            IsFqdn = lists:member($., Host),
            case IsFqdn of
                true -> longnames;
                false -> shortnames
            end;
        _ ->
            error({badarg, Node})
    end.

%% -------------------------------------------------------------------
%% Argument handling
%% -------------------------------------------------------------------
-type arg_parser(A) :: fun((term()) -> A).

-spec parse_arg(arg_parser(A), term()) -> A.
parse_arg(Parser, X) ->
    try
        Parser(X)
    catch
        error:_ -> error({badarg, X})
    end.

-spec take_arg(Key, Args0, Opts) -> {Val, Args1} when
    Key :: atom(),
    Args0 :: #{Keys => Values},
    Opts :: #{default => Val, parse := arg_parser(Val)},
    Args1 :: #{Keys => Values}.
take_arg(Key, Args0, Opts) ->
    case maps:take(Key, Args0) of
        error ->
            case Opts of
                #{default := Default} ->
                    {Default, Args0};
                #{} ->
                    error({badarg, {missing, Key}})
            end;
        {RawVal, Args1} ->
            Parser = maps:get(parse, Opts),
            try parse_arg(Parser, RawVal) of
                Val -> {Val, Args1}
            catch
                error:{badarg, RawVal} -> error({badarg, #{Key => RawVal}})
            end
    end.

-spec validate_procs_spec(Specs) -> ok when
    Specs :: [procs_spec()].
validate_procs_spec([]) ->
    ok;
validate_procs_spec([Spec | MoreSpecs]) ->
    case Spec of
        {proc, P} when is_pid(P); is_atom(P) -> ok;
        {application, A} when is_atom(A) -> ok;
        {except, P} when is_pid(P) -> ok;
        _ -> error({badarg, Spec})
    end,
    validate_procs_spec(MoreSpecs).

-spec parse_atom(term()) -> atom().
parse_atom(Atom) when is_atom(Atom) -> Atom.

-spec parse_timeout(term()) -> timeout().
parse_timeout(infinity) -> infinity;
parse_timeout(Timeout) when is_integer(Timeout), Timeout >= 0 -> Timeout.

-spec no_more_args(map()) -> ok.
no_more_args(Opts) ->
    case maps:size(Opts) of
        0 -> ok;
        _ -> error({badarg, {unknown, maps:keys(Opts)}})
    end.
