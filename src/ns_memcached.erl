%% @author Couchbase <info@couchbase.com>
%% @copyright 2010-2019 Couchbase, Inc.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%      http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%
%% This module lets you treat a memcached process as a gen_server.
%% Right now we have one of these registered per node, which stays
%% connected to the local memcached server as the admin user. All
%% communication with that memcached server is expected to pass
%% through distributed erlang, not using memcached prototocol over the
%% LAN.
%%
%% Calls to memcached that can potentially take long time are passed
%% down to one of worker processes. ns_memcached process is
%% maintaining list of ready workers and calls queue. When
%% gen_server:call arrives it is added to calls queue. And if there's
%% ready worker, it is dequeued and sent to worker. Worker then does
%% direct gen_server:reply to caller.
%%
-module(ns_memcached).

-behaviour(gen_server).

-include("ns_common.hrl").
-include("cut.hrl").

-define(CHECK_INTERVAL, 10000).
-define(CHECK_WARMUP_INTERVAL, 500).
-define(TIMEOUT,             ?get_timeout(outer, 180000)).
-define(TIMEOUT_HEAVY,       ?get_timeout(outer_heavy, 180000)).
-define(TIMEOUT_VERY_HEAVY,  ?get_timeout(outer_very_heavy, 360000)).
-define(WARMED_TIMEOUT,      ?get_timeout(warmed, 5000)).
-define(MARK_WARMED_TIMEOUT, ?get_timeout(mark_warmed, 5000)).
%% half-second is definitely 'slow' for any definition of slow
-define(SLOW_CALL_THRESHOLD_MICROS, 500000).
-define(GET_KEYS_TIMEOUT,       ?get_timeout(get_keys, 60000)).
-define(GET_KEYS_OUTER_TIMEOUT, ?get_timeout(get_keys_outer, 70000)).

-define(RECBUF, ?get_param(recbuf, 64 * 1024)).
-define(SNDBUF, ?get_param(sndbuf, 64 * 1024)).

-define(CONNECTION_ATTEMPTS, 5).

%% gen_server API
-export([start_link/1]).
-export([init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2, code_change/3]).

-record(state, {
          running_fast = 0,
          running_heavy = 0,
          running_very_heavy = 0,
          %% NOTE: otherwise dialyzer seemingly thinks it's possible
          %% for queue fields to be undefined
          fast_calls_queue = impossible :: queue:queue(),
          heavy_calls_queue = impossible :: queue:queue(),
          very_heavy_calls_queue = impossible :: queue:queue(),
          status :: connecting | init | connected | warmed,
          start_time :: undefined | tuple(),
          bucket :: bucket_name(),
          sock = still_connecting :: port() | still_connecting,
          timer :: any(),
          work_requests = [],
          warmup_stats = [] :: [{binary(), binary()}],
          check_config_pid = undefined :: undefined | pid()
         }).

%% external API
-export([active_buckets/0,
         warmed_buckets/0,
         warmed_buckets/1,
         mark_warmed/2,
         mark_warmed/1,
         disable_traffic/2,
         delete_vbucket/2,
         sync_delete_vbucket/2,
         get_vbucket_details_stats/2,
         get_single_vbucket_details_stats/3,
         host_ports/1,
         host_ports/2,
         list_vbuckets/1, list_vbuckets/2,
         local_connected_and_list_vbuckets/1,
         local_connected_and_list_vbucket_details/2,
         set_vbucket/3, set_vbucket/4,
         stats/1, stats/2,
         warmup_stats/1,
         topkeys/1,
         raw_stats/5,
         flush/1,
         set/5, add/4, get/3, delete/3,
         get_from_replica/3,
         get_meta/3,
         get_xattrs/4,
         update_with_rev/7,
         get_seqno_stats/2,
         get_mass_dcp_docs_estimate/2,
         get_dcp_docs_estimate/3,
         set_cluster_config/3,
         set_cluster_config/2,
         get_ep_startup_time_for_xdcr/1,
         perform_checkpoint_commit_for_xdcr/3,
         get_random_key/1,
         compact_vbucket/3,
         get_vbucket_high_seqno/2,
         wait_for_seqno_persistence/3,
         get_keys/3,
         config_validate/1,
         config_reload/0,
         get_failover_log/2,
         get_failover_logs/2,
         get_collections_uid/1
        ]).

%% for ns_memcached_sockets_pool, memcached_file_refresh only
-export([connect/0, connect/1]).

%% for diagnostics/debugging
-export([perform_very_long_call/2]).

-include("mc_constants.hrl").
-include("mc_entry.hrl").

%%
%% gen_server API implementation
%%

start_link(Bucket) ->
    gen_server:start_link({local, server(Bucket)}, ?MODULE, Bucket, []).


%%
%% gen_server callback implementation
%%

init(Bucket) ->
    ?log_debug("Starting ns_memcached"),
    Q = queue:new(),
    WorkersCount = case ns_config:search_node(ns_memcached_workers_count) of
                       false -> 4;
                       {value, DefinedWorkersCount} ->
                           DefinedWorkersCount
                   end,
    Self = self(),
    proc_lib:spawn_link(erlang, apply, [fun run_connect_phase/3,
                                        [Self, Bucket, WorkersCount]]),
    CollectionsCheckPid =
        proc_lib:spawn_link(erlang, apply, [fun collections_uid_check_loop/3,
                                            [Self, Bucket, undefined]]),
    ns_pubsub:subscribe_link(
      ns_config_events,
      fun ({buckets, [{configs, Configs}]}) ->
              CollectionsCheckPid ! {check, Configs};
          (_) ->
              ok
      end),
    State = #state{
               status = connecting,
               bucket = Bucket,
               work_requests = [],
               fast_calls_queue = Q,
               heavy_calls_queue = Q,
               very_heavy_calls_queue = Q,
               running_fast = WorkersCount
              },
    {ok, State}.

collections_uid_check_loop(Parent, Bucket, CollectionsUid) ->
    receive
        {check, Configs} ->
            Uid =
                case ns_bucket:get_bucket_from_configs(Bucket, Configs) of
                    {ok, BucketConfig} ->
                        case collections:uid(BucketConfig) of
                            CollectionsUid ->
                                CollectionsUid;
                            NewCollectionsUid ->
                                ?log_debug(
                                   "Triggering config check due to "
                                   "collections uid change from ~p to ~p",
                                   [CollectionsUid, NewCollectionsUid]),
                                Parent ! check_config,
                                NewCollectionsUid
                        end;
                    not_present ->
                        CollectionsUid
                end,
            collections_uid_check_loop(Parent, Bucket, Uid)
    end.

run_connect_phase(Parent, Bucket, WorkersCount) ->
    ?log_debug("Started 'connecting' phase of ns_memcached-~s. Parent is ~p", [Bucket, Parent]),
    RV = case connect() of
             {ok, Sock} ->
                 gen_tcp:controlling_process(Sock, Parent),
                 {ok, Sock};
             {error, _} = Error  ->
                 Error
         end,
    gen_server:cast(Parent, {connect_done, WorkersCount, RV}),
    erlang:unlink(Parent).

worker_init(Parent, ParentState) ->
    ParentState1 = do_worker_init(ParentState),
    worker_loop(Parent, ParentState1, #state.running_fast).

do_worker_init(State) ->
    {ok, Sock} = connect([json]),

    {ok, SockName} = inet:sockname(Sock),
    erlang:put(sockname, SockName),

    ok = mc_client_binary:select_bucket(Sock, State#state.bucket),
    State#state{sock = Sock}.

worker_loop(Parent, #state{sock = Sock} = State, PrevCounterSlot) ->
    ok = inet:setopts(Sock, [{active, once}]),
    {Msg, From, StartTS, CounterSlot} = gen_server:call(Parent, {get_work, PrevCounterSlot}, infinity),
    case inet:setopts(Sock, [{active, false}]) of
        %% Exit if socket is closed by memcached, which is possible if our
        %% previous request was erroneous.
        {error, einval} ->
            error(lost_connection);
        ok ->
            ok
    end,

    receive
        {tcp, Sock, Data} ->
            error({extra_data_on_socket, Data})
    after 0 ->
            ok
    end,

    WorkStartTS = os:timestamp(),

    erlang:put(last_call, Msg),
    case do_handle_call(Msg, From, State) of
        %% note we only accept calls that don't mutate state. So in- and
        %% out- going states asserted to be same.
        {reply, R, State} ->
            gen_server:reply(From, R);
        {compromised_reply, R, State} ->
            ?log_warning("Call ~p (return value ~p) compromised our connection. Reconnecting.",
                         [Msg, R]),
            gen_server:reply(From, R),
            error({compromised_reply, R})
    end,

    verify_report_long_call(StartTS, WorkStartTS, State, Msg, []),
    worker_loop(Parent, State, CounterSlot).

handle_call({get_work, CounterSlot}, From, #state{work_requests = Froms} = State) ->
    State2 = State#state{work_requests = [From | Froms]},
    Counter = erlang:element(CounterSlot, State2) - 1,
    State3 = erlang:setelement(CounterSlot, State2, Counter),
    {noreply, maybe_deliver_work(State3)};
handle_call(connected_and_list_vbuckets, From, State) ->
    handle_connected_call(list_vbuckets, From, State);
handle_call({connected_and_list_vbucket_details, Keys}, From, State) ->
    handle_connected_call({get_vbucket_details_stats, all, Keys}, From, State);
handle_call(warmed, From, #state{status = warmed} = State) ->
    %% A bucket is set to "warmed" state in ns_memcached,
    %% after the bucket is loaded in memcached and ns_server
    %% has enabled traffic to it.
    %% So, normally, a "warmed" state in ns_memcached also
    %% indicates that the bucket is also ready in memcached.
    %% But in some failure scenarios where memcached becomes
    %% unresponsive, it may take up to 10s for ns_memcached
    %% to realize there is an issue.
    %% So, in addition to checking ns_memcached state, also
    %% retrive stats from memcached to verify it is
    %% responsive.
    handle_call(verify_warmup, From, State);
handle_call(warmed, _From, State) ->
    {reply, false, State};
handle_call(disable_traffic, _From, State) ->
    case State#state.status of
        Status when Status =:= warmed; Status =:= connected ->
            ?log_info("Disabling traffic and unmarking bucket as warmed"),
            case mc_client_binary:disable_traffic(State#state.sock) of
                ok ->
                    State2 = State#state{status=connected,
                                         start_time = os:timestamp()},
                    {reply, ok, State2};
                {memcached_error, _, _} = Error ->
                    ?log_error("disabling traffic failed: ~p", [Error]),
                    {reply, Error, State}
            end;
        _ ->
            {reply, bad_status, State}
    end;
handle_call(mark_warmed, _From, #state{status=Status,
                                       bucket=Bucket,
                                       start_time=Start,
                                       sock=Sock} = State) ->
    {NewStatus, Reply} =
        case Status of
            connected ->
                ?log_info("Enabling traffic to bucket ~p", [Bucket]),
                case mc_client_binary:enable_traffic(Sock) of
                    ok ->
                        Time = timer:now_diff(os:timestamp(), Start) div 1000000,
                        ?log_info("Bucket ~p marked as warmed in ~p seconds",
                                  [Bucket, Time]),
                        {warmed, ok};
                    Error ->
                        ?log_error("Failed to enable traffic to bucket ~p: ~p",
                                   [Bucket, Error]),
                        {Status, Error}
                end;
            warmed ->
                {warmed, ok};
            _ ->
                {Status, bad_status}
        end,

    {reply, Reply, State#state{status=NewStatus}};
handle_call(warmup_stats, _From, State) ->
    {reply, State#state.warmup_stats, State};
handle_call(Msg, From, State) ->
    StartTS = os:timestamp(),
    NewState = queue_call(Msg, From, StartTS, State),
    {noreply, NewState}.

perform_very_long_call(Fun) ->
    perform_very_long_call(Fun, undefined).

perform_very_long_call(Fun, Bucket) ->
    perform_very_long_call(Fun, Bucket, []).

perform_very_long_call(Fun, Bucket, Options) ->
    ns_memcached_sockets_pool:executing_on_socket(
      fun (Sock) ->
              {reply, Result} = Fun(Sock),
              Result
      end, Bucket, Options).

verify_report_long_call(StartTS, ActualStartTS, State, Msg, RV) ->
    try
        RV
    after
        EndTS = os:timestamp(),
        Diff = timer:now_diff(EndTS, ActualStartTS),
        QDiff = timer:now_diff(EndTS, StartTS),
        ServiceName = "ns_memcached-" ++ State#state.bucket,
        (catch
             begin
                 system_stats_collector:increment_counter({ServiceName, call_time}, Diff),
                 system_stats_collector:increment_counter({ServiceName, q_call_time}, QDiff),
                 system_stats_collector:increment_counter({ServiceName, calls}, 1)
             end),
        if
            Diff > ?SLOW_CALL_THRESHOLD_MICROS ->
                (catch
                     begin
                         system_stats_collector:increment_counter({ServiceName, long_call_time}, Diff),
                         system_stats_collector:increment_counter({ServiceName, long_calls}, 1)
                     end),
                ?log_debug("call ~p took too long: ~p us", [Msg, Diff]);
            true ->
                ok
        end
    end.

%% anything effectful is likely to be heavy
assign_queue({delete_vbucket, _}) -> #state.very_heavy_calls_queue;
assign_queue({sync_delete_vbucket, _}) -> #state.very_heavy_calls_queue;
assign_queue(flush) -> #state.very_heavy_calls_queue;
assign_queue({set_vbucket, _, _, _}) -> #state.heavy_calls_queue;
assign_queue({add, _Key, _VBucket, _Value}) -> #state.heavy_calls_queue;
assign_queue({get, _Key, _VBucket}) -> #state.heavy_calls_queue;
assign_queue({get_from_replica, _Key, _VBucket}) -> #state.heavy_calls_queue;
assign_queue({delete, _Key, _VBucket}) -> #state.heavy_calls_queue;
assign_queue({set, _Key, _VBucket, _Value, _Flags}) -> #state.heavy_calls_queue;
assign_queue({get_keys, _VBuckets, _Params}) -> #state.heavy_calls_queue;
assign_queue({get_mass_dcp_docs_estimate, _VBuckets}) -> #state.very_heavy_calls_queue;
assign_queue({get_vbucket_details_stats, all, _}) -> #state.very_heavy_calls_queue;
assign_queue(_) -> #state.fast_calls_queue.

queue_to_counter_slot(#state.very_heavy_calls_queue) -> #state.running_very_heavy;
queue_to_counter_slot(#state.heavy_calls_queue) -> #state.running_heavy;
queue_to_counter_slot(#state.fast_calls_queue) -> #state.running_fast.

queue_call(Msg, From, StartTS, State) ->
    QI = assign_queue(Msg),
    Q = erlang:element(QI, State),
    CounterSlot = queue_to_counter_slot(QI),
    Q2 = queue:snoc(Q, {Msg, From, StartTS, CounterSlot}),
    State2 = erlang:setelement(QI, State, Q2),
    maybe_deliver_work(State2).

maybe_deliver_work(#state{running_very_heavy = RunningVeryHeavy,
                          running_fast = RunningFast,
                          work_requests = Froms} = State) ->
    case Froms of
        [] ->
            State;
        [From | RestFroms] ->
            StartedHeavy =
                %% we only consider starting heavy calls if
                %% there's extra free worker for fast calls. Thus
                %% we're considering heavy queues first. Otherwise
                %% we'll be starving them.
                case RestFroms =/= [] orelse RunningFast > 0 of
                    false ->
                        failed;
                    _ ->
                        StartedVeryHeavy =
                            case RunningVeryHeavy of
                                %% we allow only one concurrent very
                                %% heavy call. Thus it makes sense to
                                %% consider very heavy queue first
                                0 ->
                                    try_deliver_work(State, From, RestFroms, #state.very_heavy_calls_queue);
                                _ ->
                                    failed
                            end,
                        case StartedVeryHeavy of
                            failed ->
                                try_deliver_work(State, From, RestFroms, #state.heavy_calls_queue);
                            _ ->
                                StartedVeryHeavy
                        end
                end,
            StartedFast =
                case StartedHeavy of
                    failed ->
                        try_deliver_work(State, From, RestFroms, #state.fast_calls_queue);
                    _ ->
                        StartedHeavy
                end,
            case StartedFast of
                failed ->
                    State;
                _ ->
                    maybe_deliver_work(StartedFast)
            end
    end.

%% -spec try_deliver_work(#state{}, any(), [any()], (#state.very_heavy_calls_queue) | (#state.heavy_calls_queue) | (#state.fast_calls_queue)) ->
%%                               failed | #state{}.
-spec try_deliver_work(#state{}, any(), [any()], 5 | 6 | 7) ->
                              failed | #state{}.
try_deliver_work(State, From, RestFroms, QueueSlot) ->
    Q = erlang:element(QueueSlot, State),
    case queue:is_empty(Q) of
        true ->
            failed;
        _ ->
            {_Msg, _From, _StartTS, CounterSlot} = Call = queue:head(Q),
            gen_server:reply(From, Call),
            State2 = State#state{work_requests = RestFroms},
            Counter = erlang:element(CounterSlot, State2),
            State3 = erlang:setelement(CounterSlot, State2, Counter + 1),
            erlang:setelement(QueueSlot, State3, queue:tail(Q))
    end.


do_handle_call(verify_warmup,  _From, #state{bucket = Bucket,
                                             sock = Sock} = State) ->
    Stats = retrieve_warmup_stats(Sock),
    {reply, has_started(Stats, Bucket), State};
do_handle_call({raw_stats, SubStat, StatsFun, StatsFunState}, _From, State) ->
    try mc_binary:quick_stats(State#state.sock, SubStat, StatsFun, StatsFunState) of
        Reply ->
            {reply, Reply, State}
    catch T:E ->
            {reply, {exception, {T, E}}, State}
    end;
do_handle_call({delete_vbucket, VBucket}, _From, #state{sock=Sock} = State) ->
    case mc_client_binary:delete_vbucket(Sock, VBucket) of
        ok ->
            {reply, ok, State};
        {memcached_error, einval, _} ->
            ok = mc_client_binary:set_vbucket(Sock, VBucket,
                                              dead),
            Reply = mc_client_binary:delete_vbucket(Sock, VBucket),
            {reply, Reply, State}
    end;
do_handle_call({sync_delete_vbucket, VBucket}, _From, #state{sock=Sock} = State) ->
    ?log_info("sync-deleting vbucket ~p", [VBucket]),
    ok = mc_client_binary:set_vbucket(Sock, VBucket, dead),
    Reply = mc_client_binary:sync_delete_vbucket(Sock, VBucket),
    {reply, Reply, State};
do_handle_call({get_vbucket_details_stats, VBucket, Keys}, _From, State) ->
    Reply = get_vbucket_details(State#state.sock, VBucket, Keys),
    {reply, Reply, State};
do_handle_call(list_buckets, _From, State) ->
    Reply = mc_client_binary:list_buckets(State#state.sock),
    {reply, Reply, State};
do_handle_call(list_vbuckets, _From, State) ->
    Reply = mc_binary:quick_stats(
              State#state.sock, <<"vbucket">>,
              fun (<<"vb_", K/binary>>, V, Acc) ->
                      [{list_to_integer(binary_to_list(K)),
                        binary_to_existing_atom(V, latin1)} | Acc]
              end, []),
    {reply, Reply, State};
do_handle_call(flush, _From, State) ->
    Reply = mc_client_binary:flush(State#state.sock),
    {reply, Reply, State};

do_handle_call({delete, Key, VBucket}, _From, State) ->
    Reply = mc_client_binary:cmd(?DELETE, State#state.sock, undefined, undefined,
                                 {#mc_header{vbucket = VBucket},
                                  #mc_entry{key = Key}}),
    {reply, Reply, State};

do_handle_call({set, Key, VBucket, Val, Flags}, _From, State) ->
    Reply = mc_client_binary:cmd(?SET, State#state.sock, undefined, undefined,
                                 {#mc_header{vbucket = VBucket},
                                  #mc_entry{key = Key, data = Val, flag = Flags}}),
    {reply, Reply, State};

do_handle_call({add, Key, VBucket, Val}, _From, State) ->
    Reply = mc_client_binary:cmd(?ADD, State#state.sock, undefined, undefined,
                                 {#mc_header{vbucket = VBucket},
                                  #mc_entry{key = Key, data = Val}}),
    {reply, Reply, State};

do_handle_call({get, Key, VBucket}, _From, State) ->
    Reply = mc_client_binary:cmd(?GET, State#state.sock, undefined, undefined,
                                 {#mc_header{vbucket = VBucket},
                                  #mc_entry{key = Key}}),
    {reply, Reply, State};

do_handle_call({get_from_replica, Key, VBucket}, _From, State) ->
    Reply = mc_client_binary:cmd(?CMD_GET_REPLICA, State#state.sock, undefined, undefined,
                                 {#mc_header{vbucket = VBucket},
                                  #mc_entry{key = Key}}),
    {reply, Reply, State};

do_handle_call({set_vbucket, VBucket, VBState, Topology}, _From,
               #state{sock=Sock, bucket=BucketName} = State) ->
    VBInfoJson = construct_vbucket_info_json(Topology),
    (catch master_activity_events:note_vbucket_state_change(
             BucketName, node(), VBucket, VBState, VBInfoJson)),
    Reply = mc_client_binary:set_vbucket(Sock, VBucket, VBState, VBInfoJson),
    case Reply of
        ok ->
            ?log_info("Changed bucket ~p vbucket ~p state to ~p",
                      [BucketName, VBucket, VBState]);
        _ ->
            ?log_error("Failed to change bucket ~p vbucket ~p state to ~p: ~p",
                       [BucketName, VBucket, VBState, Reply])
    end,
    {reply, Reply, State};
do_handle_call({stats, Key}, _From, State) ->
    Reply = mc_binary:quick_stats(State#state.sock, Key, fun mc_binary:quick_stats_append/3, []),
    {reply, Reply, State};
do_handle_call({get_dcp_docs_estimate, VBucketId, ConnName}, _From, State) ->
    {reply, mc_client_binary:get_dcp_docs_estimate(State#state.sock, VBucketId, ConnName), State};
do_handle_call({get_mass_dcp_docs_estimate, VBuckets}, _From, State) ->
    {reply, mc_client_binary:get_mass_dcp_docs_estimate(State#state.sock, VBuckets), State};
do_handle_call({set_cluster_config, Rev, Blob}, _From,
               State = #state{bucket = Bucket, sock = Sock}) ->
    {reply, mc_client_binary:set_cluster_config(Sock, Bucket, Rev, Blob),
     State};
do_handle_call(topkeys, _From, State) ->
    Reply = mc_binary:quick_stats(
              State#state.sock, <<"topkeys">>,
              fun (K, V, Acc) ->
                      Tokens = binary:split(V, <<",">>, [global]),
                      PL = [case binary:split(S, <<"=">>) of
                                [Key, Value] ->
                                    {binary_to_atom(Key, latin1),
                                     list_to_integer(binary_to_list(Value))}
                            end || S <- Tokens],
                      [{binary_to_list(K), PL} | Acc]
              end,
              []),
    {reply, Reply, State};
do_handle_call(get_random_key, _From, State) ->
    {reply, mc_client_binary:get_random_key(State#state.sock), State};
do_handle_call({get_vbucket_high_seqno, VBucketId}, _From, State) ->
    StatName = <<"vb_", (iolist_to_binary(integer_to_list(VBucketId)))/binary, ":high_seqno">>,
    Res = mc_binary:quick_stats(
            State#state.sock, iolist_to_binary([<<"vbucket-seqno ">>, integer_to_list(VBucketId)]),
            fun (K, V, Acc) ->
                    case K of
                        StatName ->
                            list_to_integer(binary_to_list(V));
                        _ ->
                            Acc
                    end
            end,
            undefined),
    {reply, Res, State};
do_handle_call({get_keys, VBuckets, Params}, _From, State) ->
    RV = mc_binary:get_keys(State#state.sock, VBuckets, Params, ?GET_KEYS_TIMEOUT),

    case RV of
        {ok, _}  ->
            {reply, RV, State};
        {memcached_error, _} ->
            %% we take special care to leave the socket in the sane state in
            %% case of expected memcached errors (think rebalance)
            {reply, RV, State};
        {error, _} ->
            %% any other error might leave unread responses on the socket so
            %% we can't reuse it
            {compromised_reply, RV, State}
    end;

do_handle_call(_, _From, State) ->
    {reply, unhandled, State}.

handle_cast({connect_done, WorkersCount, RV}, #state{bucket = Bucket,
                                                     status = OldStatus} = State) ->
    gen_event:notify(buckets_events, {started, Bucket}),
    erlang:process_flag(trap_exit, true),

    case RV of
        {ok, Sock} ->
            try ensure_bucket(Sock, Bucket, false) of
                ok ->
                    connecting = OldStatus,

                    ?log_info("Main ns_memcached connection established: ~p",
                              [RV]),

                    {ok, Timer} = timer2:send_interval(?CHECK_WARMUP_INTERVAL,
                                                       check_started),
                    Self = self(),
                    Self ! check_started,

                    InitialState = State#state{
                                     timer = Timer,
                                     start_time = os:timestamp(),
                                     sock = Sock,
                                     status = init
                                    },
                    [proc_lib:spawn_link(erlang, apply, [fun worker_init/2,
                                                         [Self, InitialState]])
                     || _ <- lists:seq(1, WorkersCount)],
                    {noreply, InitialState};
                Error ->
                    ?log_info("ensure_bucket failed: ~p", [Error]),
                    {stop, Error}
            catch
                exit:{shutdown, reconfig} ->
                    {stop, {shutdown, reconfig}, State#state{sock = Sock}}
            end;
        Error ->
            ?log_info("Failed to establish ns_memcached connection: ~p", [RV]),
            {stop, Error}
    end;

handle_cast(start_completed, #state{start_time=Start,
                                    bucket=Bucket} = State) ->
    ale:info(?USER_LOGGER, "Bucket ~p loaded on node ~p in ~p seconds.",
             [Bucket, node(), timer:now_diff(os:timestamp(), Start) div 1000000]),
    gen_event:notify(buckets_events, {loaded, Bucket}),
    timer2:send_interval(?CHECK_INTERVAL, check_config),
    BucketConfig = case ns_bucket:get_bucket(State#state.bucket) of
                       {ok, BC} -> BC;
                       not_present -> []
                   end,
    NewStatus = case proplists:get_value(type, BucketConfig, unknown) of
                    memcached ->
                        %% memcached buckets are warmed up automagically
                        warmed;
                    _ ->
                        connected
                end,
    {noreply, State#state{status=NewStatus, warmup_stats=[]}}.


handle_info(check_started, #state{status=Status} = State)
  when Status =:= connected orelse Status =:= warmed ->
    {noreply, State};
handle_info(check_started,
            #state{timer=Timer, bucket=Bucket, sock=Sock} = State) ->
    Stats = retrieve_warmup_stats(Sock),
    case has_started(Stats, Bucket) of
        true ->
            {ok, cancel} = timer2:cancel(Timer),
            misc:flush(check_started),
            Pid = self(),
            proc_lib:spawn_link(
              fun () ->
                      memcached_passwords:sync(),
                      memcached_permissions:sync(),

                      gen_server:cast(Pid, start_completed),
                      %% we don't want exit signal in parent's message
                      %% box if everything went fine. Otherwise
                      %% ns_memcached would terminate itself (see
                      %% handle_info for EXIT message below)
                      erlang:unlink(Pid)
              end),
            {noreply, State};
        false ->
            {ok, S} = Stats,
            {noreply, State#state{warmup_stats = S}}
    end;
handle_info(check_config, #state{check_config_pid = undefined} = State) ->
    misc:flush(check_config),
    Pid = proc_lib:start_link(erlang, apply,
                              [fun run_check_and_maybe_update_config/2,
                               [State#state.bucket, self()]]),
    {noreply, State#state{check_config_pid = Pid}};
handle_info(check_config, State) ->
    {noreply, State};
handle_info({'EXIT', Pid, normal}, #state{check_config_pid = Pid} = State) ->
    {noreply, State#state{check_config_pid = undefined}};
handle_info({'EXIT', _, Reason} = Msg, State) ->
    ?log_debug("Got ~p. Exiting.", [Msg]),
    {stop, Reason, State};
handle_info(Msg, State) ->
    ?log_warning("Unexpected handle_info(~p, ~p)", [Msg, State]),
    {noreply, State}.


terminate(_Reason, #state{sock = still_connecting}) ->
    ?log_debug("Dying when socket is not yet connected");
terminate(Reason, #state{bucket=Bucket, sock=Sock}) ->
    try
        do_terminate(Reason, ns_config:get(), Bucket, Sock)
    after
        gen_event:notify(buckets_events, {stopped, Bucket}),
        ?log_debug("Terminated.")
    end.

do_terminate(Reason, Config, Bucket, Sock) ->
    BucketConfigs = ns_bucket:get_buckets(Config),
    NoBucket = not lists:keymember(Bucket, 1, BucketConfigs),
    NodeDying = (ns_config:search(Config, i_am_a_dead_man) =/= false
                 orelse not lists:member(Bucket, ns_bucket:node_bucket_names(node(), BucketConfigs))),

    Deleting = NoBucket orelse NodeDying,
    Reconfig = (Reason =:= {shutdown, reconfig}),

    case Deleting orelse Reconfig of
        true ->
            ale:info(?USER_LOGGER, "Shutting down bucket ~p on ~p for ~s",
                     [Bucket, node(), if
                                          Reconfig -> "reconfiguration";
                                          Deleting -> "deletion"
                                      end]),

            %% force = true means that that ep_engine will not try to flush
            %% outstanding mutations to disk before deleting the bucket. So we
            %% need to set it to false when we need to delete and recreate the
            %% bucket just because some setting changed.
            Force = not Reconfig,

            %% files are deleted here only when bucket is deleted; in all the
            %% other cases (like node removal or failover) we leave them on
            %% the file system and let others decide when they should be
            %% deleted
            DeleteData = NoBucket,

            delete_bucket(Sock, Bucket, Force, DeleteData);
        false ->
            %% if this is system shutdown bucket engine now can reliably
            %% delete all buckets as part of shutdown. if this is supervisor
            %% crash, we're fine too
            ale:info(?USER_LOGGER,
                     "Control connection to memcached on ~p disconnected. "
                     "Check logs for details.", [node()])
    end.

delete_bucket(Sock, Bucket, Force, DeleteData) ->
    ?log_info("Deleting bucket ~p from memcached (force = ~p)",
              [Bucket, Force]),

    try
        ok = mc_client_binary:delete_bucket(Sock, Bucket, [{force, Force}])
    catch
        T:E ->
            ?log_error("Failed to delete bucket ~p: ~p", [Bucket, {T, E}])
    after
        case DeleteData of
            true ->
                ?log_debug("Proceeding into vbuckets dbs deletions"),
                ns_couchdb_api:delete_databases_and_files(Bucket);
            false ->
                ok
        end
    end.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.


%%
%% API
%%

run_check_and_maybe_update_config(Bucket, Parent) ->
    proc_lib:init_ack(Parent, self()),
    perform_very_long_call(
      fun(Sock) ->
              StartTS = os:timestamp(),
              ok = ensure_bucket(Sock, Bucket, true),
              Diff = timer:now_diff(os:timestamp(), StartTS),
              if
                  Diff > ?SLOW_CALL_THRESHOLD_MICROS ->
                      ?log_debug("ensure_bucket took too long: ~p us", [Diff]);
                  true ->
                      ok
              end,
              {reply, ok}
      end, Bucket).

-spec active_buckets() -> [bucket_name()].
active_buckets() ->
    [Bucket || ?MODULE_STRING "-" ++ Bucket <-
                   [atom_to_list(Name) || Name <- registered()]].

-spec warmed(node(), bucket_name(), pos_integer() | infinity) -> boolean().
warmed(Node, Bucket, Timeout) ->
    try
        do_call({server(Bucket), Node}, warmed, Timeout)
    catch
        _:_ ->
            false
    end.

-spec mark_warmed([node()], bucket_name())
                 -> Result
                        when Result :: {Replies, BadNodes},
                             Replies :: [{node(), any()}],
                             BadNodes :: [node()].
mark_warmed(Nodes, Bucket) ->
    gen_server:multi_call(Nodes, server(Bucket),
                          mark_warmed, ?MARK_WARMED_TIMEOUT).

-spec mark_warmed(bucket_name()) -> any().
mark_warmed(Bucket) ->
    gen_server:call(server(Bucket), mark_warmed, ?MARK_WARMED_TIMEOUT).

warmed_buckets() ->
    warmed_buckets(?WARMED_TIMEOUT).

warmed_buckets(Timeout) ->
    RVs = misc:parallel_map(
            fun (Bucket) ->
                    {Bucket, warmed(node(), Bucket, Timeout)}
            end, active_buckets(), infinity),
    [Bucket || {Bucket, true} <- RVs].

%% @doc Send flush command to specified bucket
-spec flush(bucket_name()) -> ok.
flush(Bucket) ->
    do_call({server(Bucket), node()}, flush, ?TIMEOUT_VERY_HEAVY).


%% @doc send an add command to memcached instance
-spec add(bucket_name(), binary(), integer(), binary()) ->
                 {ok, #mc_header{}, #mc_entry{}, any()}.
add(Bucket, Key, VBucket, Value) ->
    do_call({server(Bucket), node()},
            {add, Key, VBucket, Value}, ?TIMEOUT_HEAVY).

%% @doc send get command to memcached instance
-spec get(bucket_name(), binary(), integer()) ->
                 {ok, #mc_header{}, #mc_entry{}, any()}.
get(Bucket, Key, VBucket) ->
    do_call({server(Bucket), node()}, {get, Key, VBucket}, ?TIMEOUT_HEAVY).

%% @doc send get_from_replica command to memcached instance. for testing only
-spec get_from_replica(bucket_name(), binary(), integer()) ->
                              {ok, #mc_header{}, #mc_entry{}, any()}.
get_from_replica(Bucket, Key, VBucket) ->
    do_call({server(Bucket), node()}, {get_from_replica, Key, VBucket}, ?TIMEOUT_HEAVY).

%% @doc send an get metadata command to memcached
-spec get_meta(bucket_name(), binary(), integer()) ->
                      {ok, rev(), integer(), integer()}
                          | {memcached_error, key_enoent, integer()}
                          | mc_error().
get_meta(Bucket, Key, VBucket) ->
    perform_very_long_call(
      fun (Sock) ->
              {reply, mc_client_binary:get_meta(Sock, Key, VBucket)}
      end, Bucket).

%% @doc get xattributes for specified key
-spec get_xattrs(bucket_name(), binary(), integer(), [atom()]) ->
                        {ok, integer(), [{binary(), term()}]}
                            | {memcached_error, key_enoent, integer()}
                            | mc_error().
get_xattrs(Bucket, Key, VBucket, Permissions) ->
    perform_very_long_call(
      fun (Sock) ->
              {reply, mc_binary:get_xattrs(Sock, Key, VBucket, Permissions)}
      end, Bucket, [xattr]).

%% @doc send a delete command to memcached instance
-spec delete(bucket_name(), binary(), integer()) ->
                    {ok, #mc_header{}, #mc_entry{}, any()} |
                    {memcached_error, any(), any()}.
delete(Bucket, Key, VBucket) ->
    do_call(server(Bucket), {delete, Key, VBucket}, ?TIMEOUT_HEAVY).

%% @doc send a set command to memcached instance
-spec set(bucket_name(), binary(), integer(), binary(), integer()) ->
                 {ok, #mc_header{}, #mc_entry{}, any()} |
                 {memcached_error, any(), any()}.
set(Bucket, Key, VBucket, Value, Flags) ->
    do_call({server(Bucket), node()},
            {set, Key, VBucket, Value, Flags}, ?TIMEOUT_HEAVY).

-spec update_with_rev(Bucket::bucket_name(), VBucket::vbucket_id(),
                      Id::binary(), Value::binary() | undefined, Rev :: rev(),
                      Deleted::boolean(), LocalCAS::non_neg_integer()) ->
                             {ok, #mc_header{}, #mc_entry{}} |
                             {memcached_error, atom(), binary()}.
update_with_rev(Bucket, VBucket, Id, Value, Rev, Deleted, LocalCAS) ->
    perform_very_long_call(
      fun (Sock) ->
              {reply, mc_client_binary:update_with_rev(
                        Sock, VBucket, Id, Value, Rev, Deleted, LocalCAS)}
      end, Bucket).

%% @doc Delete a vbucket. Will set the vbucket to dead state if it
%% isn't already, blocking until it successfully does so.
-spec delete_vbucket(bucket_name(), vbucket_id()) ->
                            ok | mc_error().
delete_vbucket(Bucket, VBucket) ->
    do_call(server(Bucket), {delete_vbucket, VBucket}, ?TIMEOUT_VERY_HEAVY).

-spec sync_delete_vbucket(bucket_name(), vbucket_id()) ->
                                 ok | mc_error().
sync_delete_vbucket(Bucket, VBucket) ->
    do_call(server(Bucket), {sync_delete_vbucket, VBucket},
            infinity).

-spec get_single_vbucket_details_stats(bucket_name(), vbucket_id(),
                                       all | [nonempty_string()]) ->
                                              {ok, [{nonempty_string(),
                                                     nonempty_string()}]} |
                                              mc_error().
get_single_vbucket_details_stats(Bucket, VBucket, ReqdKeys) ->
    case get_vbucket_details_stats(Bucket, VBucket, ReqdKeys) of
        {ok, Dict} ->
            case dict:find(VBucket, Dict) of
                {ok, Val} ->
                    {ok, Val};
                _ ->
                    %% In case keys aren't present in the memcached return
                    %% value.
                    {ok, []}
            end;
        Err ->
            Err
    end.

-spec get_vbucket_details_stats(bucket_name(), all | [nonempty_string()]) ->
                                       {ok, dict:dict()} | mc_error().
get_vbucket_details_stats(Bucket, ReqdKeys) ->
    get_vbucket_details_stats(Bucket, all, ReqdKeys).

-spec get_vbucket_details_stats(bucket_name(), all | vbucket_id(),
                                all | [nonempty_string()]) ->
                                       {ok, dict:dict()} | mc_error().
get_vbucket_details_stats(Bucket, VBucket, ReqdKeys) ->
    do_call(server(Bucket), {get_vbucket_details_stats, VBucket, ReqdKeys},
            ?TIMEOUT).

-spec host_ports(node(), any()) ->
                        {nonempty_string(),
                         pos_integer() | undefined,
                         pos_integer() | undefined}.
host_ports(Node, Config) ->
    [Port, SslPort] =
        [begin
             DefaultPort = service_ports:get_port(Defaultkey, Config, Node),
             ns_config:search_node_prop(Node, Config, memcached,
                                        DedicatedKey, DefaultPort)
         end || {Defaultkey, DedicatedKey} <-
                    [{memcached_port, dedicated_port},
                     {memcached_ssl_port, dedicated_ssl_port}]],
    Host = misc:extract_node_address(Node),
    {Host, Port, SslPort}.

-spec host_ports(node()) ->
                        {nonempty_string(),
                         pos_integer() | undefined,
                         pos_integer() | undefined}.
host_ports(Node) ->
    host_ports(Node, ns_config:get()).

-spec list_vbuckets(bucket_name()) ->
                           {ok, [{vbucket_id(), vbucket_state()}]} | mc_error().
list_vbuckets(Bucket) ->
    list_vbuckets(node(), Bucket).


-spec list_vbuckets(node(), bucket_name()) ->
                           {ok, [{vbucket_id(), vbucket_state()}]} | mc_error().
list_vbuckets(Node, Bucket) ->
    do_call({server(Bucket), Node}, list_vbuckets, ?TIMEOUT).

-spec local_connected_and_list_vbuckets(bucket_name()) -> warming_up | {ok, [{vbucket_id(), vbucket_state()}]}.
local_connected_and_list_vbuckets(Bucket) ->
    do_call(server(Bucket), connected_and_list_vbuckets, ?TIMEOUT).

-spec local_connected_and_list_vbucket_details(bucket_name(), [string()]) ->
                                                      warming_up |
                                                      {ok, dict:dict()}.
local_connected_and_list_vbucket_details(Bucket, Keys) ->
    do_call(server(Bucket), {connected_and_list_vbucket_details, Keys},
            ?TIMEOUT).


set_vbucket(Bucket, VBucket, VBState) ->
    set_vbucket(Bucket, VBucket, VBState, undefined).

-spec set_vbucket(bucket_name(), vbucket_id(), vbucket_state(),
                  [[node()]] | undefined) -> ok | mc_error().
set_vbucket(Bucket, VBucket, VBState, Topology) ->
    do_call(server(Bucket), {set_vbucket, VBucket, VBState, Topology},
            ?TIMEOUT_HEAVY).


-spec stats(bucket_name()) ->
                   {ok, [{binary(), binary()}]} | mc_error().
stats(Bucket) ->
    stats(Bucket, <<>>).


-spec stats(bucket_name(), binary() | string()) ->
                   {ok, [{binary(), binary()}]} | mc_error().
stats(Bucket, Key) ->
    do_call(server(Bucket), {stats, Key}, ?TIMEOUT).

-spec warmup_stats(bucket_name()) -> [{binary(), binary()}].
warmup_stats(Bucket) ->
    do_call(server(Bucket), warmup_stats, ?TIMEOUT).

-spec topkeys(bucket_name()) ->
                     {ok, [{nonempty_string(), [{atom(), integer()}]}]} |
                     mc_error().
topkeys(Bucket) ->
    do_call(server(Bucket), topkeys, ?TIMEOUT).


-spec raw_stats(node(), bucket_name(), binary(), fun(), any()) -> {ok, any()} | {exception, any()} | {error, any()}.
raw_stats(Node, Bucket, SubStats, Fn, FnState) ->
    do_call({server(Bucket), Node},
            {raw_stats, SubStats, Fn, FnState}, ?TIMEOUT).


-spec get_vbucket_high_seqno(bucket_name(), vbucket_id()) ->
                                    {ok, {undefined | seq_no()}}.
get_vbucket_high_seqno(Bucket, VBucketId) ->
    do_call(server(Bucket), {get_vbucket_high_seqno, VBucketId}, ?TIMEOUT).

-spec get_seqno_stats(ext_bucket_name(), vbucket_id() | undefined) ->
                             [{binary(), binary()}].
get_seqno_stats(Bucket, VBucket) ->
    Key = case VBucket of
              undefined ->
                  <<"vbucket-seqno">>;
              _ ->
                  list_to_binary(io_lib:format("vbucket-seqno ~B", [VBucket]))
          end,
    perform_very_long_call(
      fun (Sock) ->
              {ok, Stats} =
                  mc_binary:quick_stats(
                    Sock,
                    Key,
                    fun (K, V, Acc) ->
                            [{K, V} | Acc]
                    end, []),
              {reply, Stats}
      end, Bucket).

%%
%% Internal functions
%%

connect() ->
    connect([]).

connect(Options) ->
    Retries = proplists:get_value(retries, Options, ?CONNECTION_ATTEMPTS),
    connect(Options, Retries).

connect(Options, Tries) ->
    try
        do_connect(Options)
    catch
        E:R ->
            case Tries of
                1 ->
                    ?log_warning("Unable to connect: ~p.", [{E, R}]),
                    {error, couldnt_connect_to_memcached};
                _ ->
                    ?log_warning("Unable to connect: ~p, retrying.", [{E, R}]),
                    timer:sleep(1000), % Avoid reconnecting too fast.
                    connect(Options, Tries - 1)
            end
    end.

do_connect(Options) ->
    Config = ns_config:get(),
    Port = service_ports:get_port(memcached_dedicated_port, Config),
    User = ns_config:search_node_prop(Config, memcached, admin_user),
    Pass = ns_config:search_node_prop(Config, memcached, admin_pass),
    {ok, Sock} = gen_tcp:connect(misc:localhost(), Port,
                                 [misc:get_net_family(),
                                  binary,
                                  {packet, 0},
                                  {active, false},
                                  {recbuf, ?RECBUF},
                                  {sndbuf, ?SNDBUF}]),
    try
        case mc_client_binary:auth(Sock, {<<"PLAIN">>,
                                          {list_to_binary(User),
                                           list_to_binary(Pass)}}) of
            ok -> ok;
            Err ->
                ?log_debug("MB-34675: Login failed for <ud>~s</ud> with "
                           "provided password <ud>~s</ud>", [User, Pass]),
                error({auth_failure, Err})
        end,
        Features = mc_client_binary:hello_features(Options),
        {ok, Negotiated} = mc_client_binary:hello(Sock, "regular", Features),
        Failed = Features -- Negotiated,
        Failed == [] orelse error({feature_negotiation_failed, Failed}),
        {ok, Sock}
    catch
        T:E ->
            gen_tcp:close(Sock),
            throw({T, E})
    end.

ensure_bucket(Sock, Bucket, BucketSelected) ->
    Config = ns_config:get(),
    try memcached_bucket_config:get(Config, Bucket) of
        BConf ->
            case do_ensure_bucket(Sock, Bucket, BConf, BucketSelected) of
                ok ->
                    memcached_bucket_config:ensure_collections(Sock, BConf);
                Error ->
                    Error
            end
    catch
        E:R ->
            ?log_error("Unable to get config for bucket ~p: ~p",
                       [Bucket, {E, R, erlang:get_stacktrace()}]),
            {E, R}
    end.

do_ensure_bucket(Sock, Bucket, BConf, true) ->
    ensure_selected_bucket(Sock, Bucket, BConf);
do_ensure_bucket(Sock, Bucket, BConf, false) ->
    case mc_client_binary:select_bucket(Sock, Bucket) of
        ok ->
            ensure_selected_bucket(Sock, Bucket, BConf);
        {memcached_error, key_enoent, _} ->
            {ok, DBSubDir} =
                ns_storage_conf:this_node_bucket_dbdir(Bucket),
            ok = filelib:ensure_dir(DBSubDir),

            {Engine, ConfigString} =
                memcached_bucket_config:start_params(BConf),

            case mc_client_binary:create_bucket(Sock, Bucket, Engine,
                                                ConfigString) of
                ok ->
                    ?log_info("Created bucket ~p with config string ~p",
                              [Bucket, ConfigString]),
                    ok = mc_client_binary:select_bucket(Sock, Bucket);
                Error ->
                    {error, {bucket_create_error, Error}}
            end;
        Error ->
            {error, {bucket_select_error, Error}}
    end.

ensure_selected_bucket(Sock, Bucket, BConf) ->
    case memcached_bucket_config:ensure(Sock, BConf) of
        restart ->
            ale:info(
              ?USER_LOGGER,
              "Restarting bucket ~p due to configuration change",
              [Bucket]),
            exit({shutdown, reconfig});
        ok ->
            ok
    end.

server(Bucket) ->
    list_to_atom(?MODULE_STRING ++ "-" ++ Bucket).

retrieve_warmup_stats(Sock) ->
    mc_client_binary:stats(Sock, <<"warmup">>, fun (K, V, Acc) -> [{K, V}|Acc] end, []).

simulate_slow_warmup(Bucket) ->
    TestCondition = {ep_slow_bucket_warmup, Bucket},
    case testconditions:get(TestCondition) of
        false ->
            false;
        0 ->
            false;
        Delay ->
            NewDelay = case Delay =< ?CHECK_WARMUP_INTERVAL of
                           true ->
                               0;
                           _ ->
                               Delay - ?CHECK_WARMUP_INTERVAL
                       end,
            ?log_debug("Simulating slow warmup of bucket ~p. Pending delay ~p seconds", [Bucket, Delay/1000]),
            testconditions:set(TestCondition, NewDelay),
            true
    end.

has_started({memcached_error, key_enoent, _}, _) ->
    %% this is memcached bucket, warmup is done :)
    true;
has_started(Stats, Bucket) ->
    case simulate_slow_warmup(Bucket) of
        false ->
            has_started_inner(Stats);
        true ->
            false
    end.

has_started_inner({ok, WarmupStats}) ->
    case lists:keyfind(<<"ep_warmup_thread">>, 1, WarmupStats) of
        {_, <<"complete">>} ->
            true;
        {_, V} when is_binary(V) ->
            false
    end.

do_call(Server, Msg, Timeout) ->
    StartTS = os:timestamp(),
    try
        gen_server:call(Server, Msg, Timeout)
    after
        try
            EndTS = os:timestamp(),
            Diff = timer:now_diff(EndTS, StartTS),
            Service = case Server of
                          _ when is_atom(Server) ->
                              atom_to_list(Server);
                          _ ->
                              "unknown"
                      end,
            system_stats_collector:increment_counter({Service, e2e_call_time}, Diff),
            system_stats_collector:increment_counter({Service, e2e_calls}, 1)
        catch T:E ->
                ?log_debug("failed to measure ns_memcached call:~n~p", [{T,E,erlang:get_stacktrace()}])
        end
    end.

-spec disable_traffic(bucket_name(), non_neg_integer() | infinity) -> ok | bad_status | mc_error().
disable_traffic(Bucket, Timeout) ->
    gen_server:call(server(Bucket), disable_traffic, Timeout).

-spec wait_for_seqno_persistence(bucket_name(), vbucket_id(), seq_no()) -> ok | mc_error().
wait_for_seqno_persistence(Bucket, VBucketId, SeqNo) ->
    perform_very_long_call(
      fun (Sock) ->
              {reply, mc_client_binary:wait_for_seqno_persistence(Sock, VBucketId, SeqNo)}
      end, Bucket).

-spec compact_vbucket(bucket_name(), vbucket_id(),
                      {integer(), integer(), boolean()}) ->
                             ok | mc_error().
compact_vbucket(Bucket, VBucket, {PurgeBeforeTS, PurgeBeforeSeqNo, DropDeletes}) ->
    perform_very_long_call(
      fun (Sock) ->
              {reply, mc_client_binary:compact_vbucket(Sock, VBucket,
                                                       PurgeBeforeTS, PurgeBeforeSeqNo, DropDeletes)}
      end, Bucket).


-spec get_dcp_docs_estimate(bucket_name(), vbucket_id(), string()) ->
                                   {ok, {non_neg_integer(), non_neg_integer(), binary()}}.
get_dcp_docs_estimate(Bucket, VBucketId, ConnName) ->
    do_call(server(Bucket), {get_dcp_docs_estimate, VBucketId, ConnName}, ?TIMEOUT).

-spec get_mass_dcp_docs_estimate(bucket_name(), [vbucket_id()]) ->
                                        {ok, [{non_neg_integer(), non_neg_integer(), binary()}]}.
get_mass_dcp_docs_estimate(Bucket, VBuckets) ->
    do_call(server(Bucket), {get_mass_dcp_docs_estimate, VBuckets}, ?TIMEOUT_VERY_HEAVY).

-spec set_cluster_config(bucket_name(), integer(), binary()) -> ok | mc_error().
set_cluster_config(Bucket, Rev, Blob) ->
    do_call(server(Bucket), {set_cluster_config, Rev, Blob}, ?TIMEOUT).

%% The function might be rpc'ed beginning from Mad-Hatter
get_random_key(Bucket) ->
    do_call(server(Bucket), get_random_key, ?TIMEOUT).

get_ep_startup_time_for_xdcr(Bucket) ->
    perform_very_long_call(
      fun (Sock) ->
              {ok, StartupTime} =
                  mc_binary:quick_stats(
                    Sock, <<>>,
                    fun (K, V, Acc) ->
                            case K =:= <<"ep_startup_time">> of
                                true -> V;
                                _ -> Acc
                            end
                    end, undefined),
              false = StartupTime =:= undefined,
              {reply, StartupTime}
      end, Bucket).

perform_checkpoint_commit_for_xdcr(Bucket, VBucketId, Timeout) ->
    perform_very_long_call(fun (Sock) -> do_perform_checkpoint_commit_for_xdcr(Sock, VBucketId, Timeout) end, Bucket).

do_perform_checkpoint_commit_for_xdcr(Sock, VBucketId, Timeout) ->
    case Timeout of
        infinity -> ok;
        _ -> timer2:exit_after(Timeout, timeout)
    end,
    StatsKey = iolist_to_binary(io_lib:format("vbucket-seqno ~B", [VBucketId])),
    SeqnoKey = iolist_to_binary(io_lib:format("vb_~B:high_seqno", [VBucketId])),
    {ok, Seqno} = mc_binary:quick_stats(Sock, StatsKey,
                                        fun (K, V, Acc) ->
                                                case K =:= SeqnoKey of
                                                    true -> list_to_integer(binary_to_list(V));
                                                    _ -> Acc
                                                end
                                        end, []),
    case is_integer(Seqno) of
        true ->
            do_perform_checkpoint_commit_for_xdcr_loop(Sock, VBucketId, Seqno);
        _ ->
            {reply, {memcached_error, not_my_vbucket}}
    end.

do_perform_checkpoint_commit_for_xdcr_loop(Sock, VBucketId, WaitedSeqno) ->
    case mc_client_binary:wait_for_seqno_persistence(Sock,
                                                     VBucketId,
                                                     WaitedSeqno) of
        ok -> {reply, ok};
        {memcached_error, etmpfail, _} ->
            do_perform_checkpoint_commit_for_xdcr_loop(Sock, VBucketId, WaitedSeqno);
        {memcached_error, OtherError, _} ->
            {reply, {memcached_error, OtherError}}
    end.

get_keys(Bucket, NodeVBuckets, Params) ->
    try
        {ok, do_get_keys(Bucket, NodeVBuckets, Params)}
    catch
        exit:timeout ->
            {error, timeout}
    end.

do_get_keys(Bucket, NodeVBuckets, Params) ->
    misc:parallel_map(
      fun ({Node, VBuckets}) ->
              try do_call({server(Bucket), Node},
                          {get_keys, VBuckets, Params}, infinity) of
                  unhandled ->
                      {Node, {ok, []}};
                  R ->
                      {Node, R}
              catch
                  T:E ->
                      {Node, {T, E}}
              end
      end, NodeVBuckets, ?GET_KEYS_OUTER_TIMEOUT).

-spec config_validate(binary()) -> ok | mc_error().
config_validate(NewConfig) ->
    misc:executing_on_new_process(
      fun () ->
              {ok, Sock} = connect([{retries, 1}]),
              mc_client_binary:config_validate(Sock, NewConfig)
      end).

config_reload() ->
    misc:executing_on_new_process(
      fun () ->
              {ok, Sock} = connect([{retries, 1}]),
              mc_client_binary:config_reload(Sock)
      end).

-spec get_failover_log(bucket_name(), vbucket_id()) ->
                              [{integer(), integer()}] | mc_error().
get_failover_log(Bucket, VBucket) ->
    perform_very_long_call(
      ?cut({reply, mc_client_binary:get_failover_log(_, VBucket)}), Bucket).

-spec get_failover_logs(bucket_name(), [vbucket_id()]) -> Result when
      Result :: Success | Error,
      Success :: {ok, [{vbucket_id(), FailoverLog}]},
      FailoverLog :: [{integer(), integer()}],
      Error :: {error, {failed_to_get_failover_log,
                        bucket_name(), vbucket_id(), mc_error()}}.
get_failover_logs(Bucket, VBuckets) ->
    %% TODO: consider using "failovers" stat instead
    perform_very_long_call(
      ?cut({reply, get_failover_logs_loop(_, VBuckets, [])}), Bucket).

get_failover_logs_loop(_Sock, [], Acc) ->
    {ok, lists:reverse(Acc)};
get_failover_logs_loop(Sock, [V | VBs], Acc) ->
    case mc_client_binary:get_failover_log(Sock, V) of
        FailoverLog when is_list(FailoverLog) ->
            get_failover_logs_loop(Sock, VBs, [FailoverLog | Acc]);
        Error ->
            {error, {failed_to_get_failover_log, V, Error}}
    end.

-spec set_cluster_config(integer(), binary()) -> ok | mc_error().
set_cluster_config(Rev, Blob) ->
    perform_very_long_call(
      ?cut({reply, mc_client_binary:set_cluster_config(_, "", Rev, Blob)})).

get_collections_uid(Bucket) ->
    collections:convert_uid_from_memcached(
      perform_very_long_call(
        ?cut({reply, memcached_bucket_config:get_current_collections_uid(_)}),
        Bucket)).

handle_connected_call(Call, From, #state{status = Status} = State) ->
    case Status of
        S when (S =:= init orelse S =:= connecting) ->
            {reply, warming_up, State};
        _ ->
            handle_call(Call, From, State)
    end.

construct_topology(Topology) ->
    [lists:map(fun (undefined) ->
                       null;
                   (Node) ->
                       Node
               end, Chain) || Chain <- Topology].

construct_topology_json(Topology) ->
    {[{topology, construct_topology(Topology)}]}.

construct_vbucket_info_json(undefined) ->
    undefined;
construct_vbucket_info_json(Topology) ->
    construct_topology_json(Topology).

get_vbucket_details(Sock, all, ReqdKeys) ->
    get_vbucket_details_inner(Sock, <<"vbucket-details">>, ReqdKeys);
get_vbucket_details(Sock, VBucket, ReqdKeys) when is_integer(VBucket) ->
    VBucketStr = integer_to_list(VBucket),
    get_vbucket_details_inner(
      Sock, iolist_to_binary([<<"vbucket-details ">>, VBucketStr]), ReqdKeys).

get_vbucket_details_inner(Sock, DetailsKey, ReqdKeys) ->
    mc_binary:quick_stats(
      Sock, DetailsKey,
      fun (<<"vb_", VBKey/binary>>, BinVal, Dict) ->
              {VB, Key} = case binary:split(VBKey, [<<":">>]) of
                              [BinVB, BinK] -> {BinVB, binary_to_list(BinK)};
                              [BinVB] -> {BinVB, "state"}
                          end,
              case ReqdKeys =:= all orelse lists:member(Key, ReqdKeys) of
                  true ->
                      VBucket = list_to_integer(binary_to_list(VB)),
                      NewVal = [{Key, binary_to_list(BinVal)}],
                      dict:update(VBucket,
                                  fun (OldVal) ->
                                          NewVal ++ OldVal
                                  end, NewVal, Dict);
                  false ->
                      Dict
              end
      end, dict:new()).
