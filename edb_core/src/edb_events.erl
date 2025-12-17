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
-module(edb_events).
-compile(warn_missing_spec_all).

-oncall("whatsapp_server_devx").
-compile(warn_missing_spec_all).

-moduledoc false.

%% Public API
-export([no_subscribers/0]).
-export([subscribe/3, subscribe/4]).
-export([unsubscribe/2, process_down/2]).
-export([subscriber_pids/1, subscribers/1, subscriptions/1]).
-export([send_to/3, broadcast/2]).

-export_type([event/0]).
-export_type([subscription/0]).
-export_type([subscribers/0]).
-export_type([monitor_ref/0]).

%% -------------------------------------------------------------------
%% Types
%% -------------------------------------------------------------------

-type event() :: edb:event().
-opaque subscription() :: reference().
-opaque subscribers() :: #{
    subscriptions := #{subscription() => {pid(), monitor_ref()}},
    monitors := #{monitor_ref() => subscription()}
}.
-type monitor_ref() :: reference().

%% -------------------------------------------------------------------
%% Create and update
%% -------------------------------------------------------------------

-spec no_subscribers() -> subscribers().
no_subscribers() ->
    #{subscriptions => #{}, monitors => #{}}.

-spec subscribe(Pid, MonitorRef, Subscribers) -> {ok, {Subscription, Subscribers}} when
    Pid :: pid(),
    MonitorRef :: monitor_ref(),
    Subscription :: subscription(),
    Subscribers :: subscribers().
subscribe(Pid, MonitorRef, Subscribers0) ->
    Subscription = erlang:make_ref(),
    {ok, Subscribers1} = subscribe(Subscription, Pid, MonitorRef, Subscribers0),
    {ok, {Subscription, Subscribers1}}.

-spec subscribe(Subscription, Pid, MonitorRef, Subscribers) -> {ok, Subscribers} when
    Subscription :: subscription(),
    Pid :: pid(),
    MonitorRef :: monitor_ref(),
    Subscribers :: subscribers().
subscribe(Subscription, _Pid, _MonitorRef, #{subscriptions := Subs}) when is_map_key(Subscription, Subs) ->
    error({duplicate_subscription, Subscription});
subscribe(Subscription, Pid, MonitorRef, #{subscriptions := Subs0, monitors := Mon0}) when
    is_pid(Pid), is_reference(MonitorRef), not is_map_key(MonitorRef, Mon0)
->
    Subs1 = Subs0#{Subscription => {Pid, MonitorRef}},
    Mon1 = Mon0#{MonitorRef => Subscription},
    {ok, #{subscriptions => Subs1, monitors => Mon1}}.

-spec unsubscribe(Subscription, Subscribers) -> not_subscribed | {ok, {MonitorRef, Subscribers}} when
    Subscription :: subscription(),
    Subscribers :: subscribers(),
    MonitorRef :: monitor_ref().
unsubscribe(Subscription, #{subscriptions := Subs0, monitors := Mon0}) when is_reference(Subscription) ->
    case maps:take(Subscription, Subs0) of
        error ->
            not_subscribed;
        {{_Pid, MonitorRef}, Subs1} ->
            Mon1 = maps:remove(MonitorRef, Mon0),
            {ok, {MonitorRef, #{subscriptions => Subs1, monitors => Mon1}}}
    end.

-spec process_down(MonitorRef, Subscribers) -> Subscribers when
    MonitorRef :: monitor_ref(),
    Subscribers :: subscribers().
process_down(MonitorRef, Subscribers0 = #{monitors := Mon0}) ->
    case Mon0 of
        #{MonitorRef := Subscription} ->
            {ok, {MonitorRef, Subscribers1}} = unsubscribe(Subscription, Subscribers0),
            Subscribers1;
        _ ->
            Subscribers0
    end.

%% -------------------------------------------------------------------
%% Query
%% -------------------------------------------------------------------

-spec subscriber_pids(subscribers()) -> [pid()].
subscriber_pids(#{subscriptions := Subscriptions}) ->
    [Pid || _Subscription := {Pid, _MonitorRef} <- Subscriptions].

-spec subscribers(subscribers()) -> #{subscription() => pid()}.
subscribers(#{subscriptions := Subscriptions}) ->
    #{Subscription => Pid || Subscription := {Pid, _MonitorRef} <- Subscriptions}.

-spec subscriptions(subscribers()) -> [subscription()].
subscriptions(#{subscriptions := Subscriptions}) ->
    maps:keys(Subscriptions).

%% -------------------------------------------------------------------
%% Send events
%% -------------------------------------------------------------------

-spec send_to(Subscription, Event, Subscribers) -> ok | undefined when
    Subscription :: subscription(),
    Event :: event(),
    Subscribers :: subscribers().
send_to(Subscription, Event, #{subscriptions := Subscriptions}) when is_reference(Subscription) ->
    case Subscriptions of
        #{Subscription := {Pid, _MonitorRef}} ->
            Pid ! {edb_event, Subscription, Event},
            ok;
        _ ->
            undefined
    end.

-spec broadcast(Event, Subscribers) -> ok when
    Event :: event(),
    Subscribers :: subscribers().
broadcast(Event, #{subscriptions := Subscriptions}) ->
    [Pid ! {edb_event, Subscription, Event} || Subscription := {Pid, _MonitorRef} <- Subscriptions],
    ok.
