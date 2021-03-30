%% @author Couchbase, Inc <info@couchbase.com>
%% @copyright 2011-2020 Couchbase, Inc.
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
%% @doc grabs system-level stats portsigar
%%
-module(ns_server_stats).

-behaviour(gen_server).

-include_lib("stdlib/include/assert.hrl").
-include("ns_common.hrl").
-include("ns_stats.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-define(ETS_LOG_INTVL, 180).

-define(DEFAULT_HIST_MAX, 10000). %%  10^4, 4 buckets
-define(DEFAULT_HIST_UNIT, millisecond).
-define(METRIC_PREFIX, <<"cm_">>).

%% API
-export([start_link/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-export([init_stats/0, notify_counter/1, notify_counter/2, notify_gauge/2,
         notify_histogram/2, notify_histogram/4, notify_max/2]).

-export([increment_counter/1, increment_counter/2,
         get_ns_server_stats/0, set_counter/2,
         add_histo/2,
         cleanup_stale_epoch_histos/0, log_system_stats/1,
         stale_histo_epoch_cleaner/0, report_prom_stats/2]).

-type os_pid() :: integer().

-record(state, {
          port      :: port() | undefined,
          pid_names :: [{os_pid(), binary()}],
          prev      :: term()
         }).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

notify_counter(Metric) ->
    notify_counter(Metric, 1).
notify_counter(Metric, Val) when Val > 0, is_integer(Val) ->
    Key = {c, normalized_metric(Metric)},
    catch ets:update_counter(?MODULE, Key, Val, {Key, 0}),
    ok.

notify_gauge(Metric, Val) ->
    Key = {g, normalized_metric(Metric)},
    catch ets:insert(?MODULE, {Key, Val}),
    ok.

notify_histogram(Metric, Val) ->
    notify_histogram(Metric, ?DEFAULT_HIST_MAX, ?DEFAULT_HIST_UNIT, Val).
notify_histogram(Metric, Max, Units, Val) when Max > 0, Val >= 0,
                                               is_integer(Val) ->
    BucketN = get_histogram_bucket(Val, Max),
    Key = {h, normalized_metric(Metric), Max, Units},
            %% Update sum | Update counter for a particular bucket
    Updates = [{2, Val},    {BucketN + 4, 1}],
    try ets:update_counter(?MODULE, Key, Updates) of
        _ -> ok
    catch
        error:badarg -> %% missing stat or no ets table
            N = get_histogram_bucket(Max, Max) + 1,
            %%                      Sum | Inf | Other Buckets
            V = list_to_tuple([Key,   0,    0 | lists:duplicate(N, 0)]),
            %% verify units
            ?assert(is_number(to_seconds(1, Units))),
            catch ets:insert_new(?MODULE, V),
            catch ets:update_counter(?MODULE, Key, Updates),
            ok
    end.

%% It is unsafe to use this function from multiple processes with the same
%% metric
notify_max({Metric, Window, BucketSize}, Val) ->
    Now = erlang:monotonic_time(millisecond),
    notify_moving_window(max, Metric, Window, BucketSize, Now, ?MODULE, Val).

report_prom_stats(ReportFun, IsHighCard) ->
    Try = fun (Name, F) ->
              try F()
              catch C:E:ST ->
                  ?log_error("~p stats reporting exception: ~p:~p~n~p",
                             [Name, C, E, ST])
              end
          end,
    case IsHighCard of
        true ->
            Try(ns_server, fun () -> report_ns_server_hc_stats(ReportFun) end);
        false ->
            Try(ns_server, fun () -> report_ns_server_lc_stats(ReportFun) end),
            Try(audit, fun () -> report_audit_stats(ReportFun) end),
            Try(system, fun () -> report_system_stats(ReportFun) end),
            Try(couchdb, fun () -> report_couchdb_stats(ReportFun) end)
    end,
    ok.

report_system_stats(ReportFun) ->
    Stats = gen_server:call(?MODULE, get_stats),
    SystemStats = proplists:get_value("@system", Stats, []),
    lists:foreach(
      fun ({Key, Val}) ->
          ReportFun({<<"sys">>, Key, [{<<"category">>, <<"system">>}], Val})
      end, SystemStats),

    SysProcStats = proplists:get_value("@system-processes", Stats, []),
    lists:foreach(
        fun ({KeyBin, Val}) ->
            [Proc, Name] = binary:split(KeyBin, <<"/">>),
            ReportFun({<<"sysproc">>, Name,
                       [{<<"proc">>, Proc},
                        {<<"category">>, <<"system-processes">>}], Val})
        end, SysProcStats).

report_audit_stats(ReportFun) ->
    {ok, Stats} = ns_audit:stats(),
    AuditQueueLen = proplists:get_value(queue_length, Stats, 0),
    AuditRetries = proplists:get_value(unsuccessful_retries, Stats, 0),
    ReportFun({<<"audit">>, <<"queue_length">>,
              [{<<"category">>, <<"audit">>}], AuditQueueLen}),
    ReportFun({<<"audit">>, <<"unsuccessful_retries">>,
              [{<<"category">>, <<"audit">>}], AuditRetries}).

report_couchdb_stats(ReportFun) ->
    ThisNodeBuckets = ns_bucket:node_bucket_names_of_type(node(), membase),
    [report_couch_stats(B, ReportFun) || B <- ThisNodeBuckets].

report_couch_stats(Bucket, ReportFun) ->
    Stats = try
                ns_couchdb_api:fetch_raw_stats(Bucket)
            catch
                _:E:ST ->
                    ?log_info("Failed to fetch couch stats:~p~n~p", [E, ST]),
                    []
            end,
    ViewsStats = proplists:get_value(views_per_ddoc_stats, Stats, []),
    SpatialStats = proplists:get_value(spatial_per_ddoc_stats, Stats, []),
    DocsDiskSize = proplists:get_value(couch_docs_actual_disk_size, Stats),
    ViewsDiskSize = proplists:get_value(couch_views_actual_disk_size, Stats),

    Labels = [{<<"bucket">>, Bucket}],
    case DocsDiskSize of
        undefined -> ok;
        _ -> ReportFun({couch_docs_actual_disk_size, Labels, DocsDiskSize})
    end,
    case ViewsDiskSize of
        undefined -> ok;
        _ -> ReportFun({couch_views_actual_disk_size, Labels, ViewsDiskSize})
    end,
    lists:foreach(
      fun ({Sig, Disk, Data, Ops}) ->
            L = [{<<"signature">>, Sig} | Labels],
            ReportFun({couch_views_disk_size, L, Disk}),
            ReportFun({couch_views_data_size, L, Data}),
            ReportFun({couch_views_ops, L, Ops})
      end, ViewsStats),
    lists:foreach(
      fun ({Sig, Disk, Data, Ops}) ->
            L = [{<<"signature">>, Sig} | Labels],
            ReportFun({couch_spatial_disk_size, L, Disk}),
            ReportFun({couch_spatial_data_size, L, Data}),
            ReportFun({couch_spatial_ops, L, Ops})
      end, SpatialStats).

report_ns_server_lc_stats(ReportFun) ->
    lists:foreach(
      fun (Key) ->
          case ets:lookup(?MODULE, Key) of
              [] -> ok;
              [M] -> report_stat(M, ReportFun)
          end
      end, low_cardinality_stats()).

report_ns_server_hc_stats(ReportFun) ->
    ets:foldl(
      fun (M, _) ->
          case lists:member(element(1, M), low_cardinality_stats()) of
              true -> ok;
              false -> report_stat(M, ReportFun)
          end,
          ok
      end, [], ?MODULE),
    ok.

low_cardinality_stats() ->
    [{c, {<<"rest_request_enters">>, []}},
     {c, {<<"rest_request_leaves">>, []}}].

report_stat({{g, {BinName, Labels}}, Value}, ReportFun) ->
    ReportFun({[?METRIC_PREFIX, BinName], Labels, Value});
report_stat({{c, {BinName, Labels}}, Value}, ReportFun) ->
    NameIOList = [[?METRIC_PREFIX, BinName], <<"_total">>],
    ReportFun({NameIOList, Labels, Value});
report_stat({{mw, F, Window, {BinName, Labels}}, BucketsQ}, ReportFun) ->
    Now = erlang:monotonic_time(millisecond),
    PrunedBucketsQ = prune_buckets(Now - Window, BucketsQ),
    Values = [V || {_, V} <- queue:to_list(PrunedBucketsQ)],
    Value = aggregate_moving_window_buckets(F, Values),
    ReportFun({[?METRIC_PREFIX, BinName], Labels, Value});
report_stat(Histogram, ReportFun) ->
    [{h, {Name, Labels}, _Max, Units}, Sum, Inf | Buckets] =
        tuple_to_list(Histogram),
    BinName = iolist_to_binary([Name, <<"_seconds">>]),

    BucketName = [?METRIC_PREFIX, BinName, <<"_bucket">>],
    {_, BucketsTotal} =
        lists:foldl(
          fun (Val, {Le, CurTotal}) ->
              BucketValue = CurTotal + Val,
              ReportFun({BucketName,
                         [{le, to_seconds(Le, Units)} | Labels],
                         BucketValue}),
              {Le * 10, BucketValue}
          end, {1, 0}, Buckets),
    Total = BucketsTotal + Inf,
    ReportFun({BucketName, [{le, <<"+Inf">>}| Labels], Total}),
    ReportFun({[?METRIC_PREFIX, BinName, <<"_count">>], Labels,
               Total}),
    ReportFun({[?METRIC_PREFIX, BinName, <<"_sum">>], Labels,
               to_seconds(Sum, Units)}).

init([]) ->
    init_stats(),
    increment_counter({request_leaves, rest}, 0),
    increment_counter({request_enters, hibernate}, 0),
    increment_counter({request_leaves, hibernate}, 0),
    increment_counter(log_counter, 0),
    increment_counter(odp_report_failed, 0),
    _ = spawn_link(fun stale_histo_epoch_cleaner/0),

    Port = spawn_sigar(),
    spawn_ale_stats_collector(),

    State = #state{port = Port,
                   pid_names = grab_pid_names()},

    {ok, State}.

init_stats() ->
    ets:new(?MODULE, [public, named_table, set]),
    %% Deprecated table, will be removed:
    ets:new(ns_server_system_stats, [public, named_table, set]).

spawn_sigar() ->
    Path = path_config:component_path(bin, "sigar_port"),
    BabysitterPid = ns_server:get_babysitter_pid(),
    Name = lists:flatten(io_lib:format("portsigar for ~s", [node()])),
    open_port({spawn_executable, Path},
              [stream, use_stdio, exit_status, binary, eof,
               {arg0, Name},
               {args, [integer_to_list(BabysitterPid)]}]).

handle_call(get_stats, _From, State = #state{port = Port, prev = Prev}) ->
    Data = grab_stats(Port),
    {Stats, NewPrev} =
        process_stats(os:system_time(millisecond), Data, Prev, State),
    {reply, Stats, State#state{prev = NewPrev}};

%% Can be called from another node. Introduced in 7.0
handle_call({stats_interface, Function, Args}, From, State) ->
    _ = proc_lib:spawn_link(
          fun () ->
              Res = erlang:apply(stats_interface, Function, Args),
              gen_server:reply(From, Res)
          end),
    {noreply, State};

handle_call(_Request, _From, State) ->
    {noreply, State}.

%% Can be called from another node. Introduced in 7.0
handle_cast({extract, {From, Ref}, Query, Start, End, Step, Timeout}, State) ->
    Settings = prometheus_cfg:settings(),
    Reply = fun (Res) -> From ! {Ref, Res} end,
    prometheus:query_range_async(Query, Start, End, Step, Timeout,
                                 Settings, Reply),
    {noreply, State};
handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

recv_data(Port) ->
    recv_data_loop(Port, <<"">>).

recv_data_loop(Port, <<Version:32/native,
                       StructSize:32/native, _/binary>> = Acc)
  when Version =:= 5 ->
    recv_data_with_length(Port, Acc, StructSize - erlang:size(Acc));
recv_data_loop(_, <<Version:32/native, _/binary>>) ->
    error({unsupported_portsigar_version, Version});
recv_data_loop(Port, Acc) ->
    receive
        {Port, {data, Data}} ->
            recv_data_loop(Port, <<Data/binary, Acc/binary>>)
    end.

recv_data_with_length(_Port, Acc, _WantedLength = 0) ->
    erlang:iolist_to_binary(Acc);
recv_data_with_length(Port, Acc, WantedLength) ->
    receive
        {Port, {data, Data}} ->
            Size = size(Data),
            if
                Size =< WantedLength ->
                    recv_data_with_length(Port, [Acc | Data],
                                          WantedLength - Size);
                Size > WantedLength ->
                    erlang:error({too_big_recv, Size, WantedLength, Data, Acc})
            end
    end.

unpack_data({Bin, LocalStats}, PrevCounters, State) ->
    <<_Version:32/native,
      StructSize:32/native,
      CPUTotalMS:64/native,
      CPUIdleMS:64/native,
      CPUUserMS:64/native,
      CPUSysMS:64/native,
      CPUIrqMS:64/native,
      CPUStolenMS:64/native,
      SwapTotal:64/native,
      SwapUsed:64/native,
      MemTotal:64/native,
      MemUsed:64/native,
      MemActualUsed:64/native,
      MemActualFree:64/native,
      AllocStall:64/native,
      Rest/binary>> = Bin,

    StructSize = erlang:size(Bin),

    NowSamplesProcs0 = unpack_processes(Rest, State),

    NowSamplesProcs =
        case NowSamplesProcs0 of
            [] ->
                undefined;
            _ ->
                NowSamplesProcs0
        end,

    #{cgroup_mem := CGroupMem, cpu_count := CPUcount} = LocalStats,
    {MemLimit, _} = memory_quota:choose_limit(MemTotal, MemUsed, CGroupMem),
    CoresAvailable = case CPUcount of
                         unknown -> 0;
                         N -> N
                     end,

    Counters = #{cpu_total_ms => CPUTotalMS,
                 cpu_idle_ms => CPUIdleMS,
                 cpu_user_ms => CPUUserMS,
                 cpu_sys_ms => CPUSysMS,
                 cpu_irq_ms => CPUIrqMS,
                 cpu_stolen_ms => CPUStolenMS},
    NowSamplesGlobal =
        case PrevCounters of
            undefined ->
                undefined;
            _ ->
                compute_cpu_stats(PrevCounters, Counters) ++
                    [{cpu_cores_available, CoresAvailable},
                     {swap_total, SwapTotal},
                     {swap_used, SwapUsed},
                     {mem_limit, MemLimit},
                     {mem_total, MemTotal},
                     {mem_used_sys, MemUsed},
                     {mem_actual_used, MemActualUsed},
                     {mem_actual_free, MemActualFree},
                     {mem_free, MemActualFree},
                     {allocstall, AllocStall}]
        end,

    {{NowSamplesGlobal, NowSamplesProcs}, Counters}.

unpack_processes(Bin, State) ->
    NewSample0 = do_unpack_processes(Bin, [], State),
    collapse_duplicates(NewSample0).

collapse_duplicates(Sample) ->
    Sorted = lists:keysort(1, Sample),
    lists:foldl(fun do_collapse_duplicates/2, [], Sorted).

do_collapse_duplicates({K, V1}, [{K, V2} | Acc]) ->
    [{K, V1 + V2} | Acc];
do_collapse_duplicates(KV, Acc) ->
    [KV | Acc].

do_unpack_processes(Bin, Acc, _) when size(Bin) =:= 0 ->
    Acc;
do_unpack_processes(Bin, NewSampleAcc, State) ->
    <<Name0:60/binary,
      CpuUtilization:32/native,
      Pid:64/native,
      _PPid:64/native,
      MemSize:64/native,
      MemResident:64/native,
      MemShare:64/native,
      MinorFaults:64/native,
      MajorFaults:64/native,
      PageFaults:64/native,
      Rest/binary>> = Bin,

    RawName = extract_string(Name0),
    case RawName of
        <<>> ->
            NewSampleAcc;
        _ ->
            Name = adjust_process_name(Pid, RawName, State),

            NewSample =
                [{proc_stat_name(Name, mem_size), MemSize},
                 {proc_stat_name(Name, mem_resident), MemResident},
                 {proc_stat_name(Name, mem_share), MemShare},
                 {proc_stat_name(Name, cpu_utilization), CpuUtilization},
                 {proc_stat_name(Name, minor_faults_raw), MinorFaults},
                 {proc_stat_name(Name, major_faults_raw), MajorFaults},
                 {proc_stat_name(Name, page_faults_raw), PageFaults}],

            Acc1 = NewSample ++ NewSampleAcc,
            do_unpack_processes(Rest, Acc1, State)
    end.

extract_string(Bin) ->
    do_extract_string(Bin, size(Bin) - 1).

do_extract_string(_Bin, 0) ->
    <<>>;
do_extract_string(Bin, Pos) ->
    case binary:at(Bin, Pos) of
        0 ->
            do_extract_string(Bin, Pos - 1);
        _ ->
            binary:part(Bin, 0, Pos + 1)
    end.

proc_stat_name(Name, Stat) ->
    <<Name/binary, $/, (atom_to_binary(Stat, latin1))/binary>>.

log_system_stats(TS) ->
    NSServerStats = lists:sort(ets:tab2list(ns_server_system_stats)),
    NSCouchDbStats = ns_couchdb_api:fetch_stats(),

    log_stats(TS, "@system", lists:keymerge(1, NSServerStats, NSCouchDbStats)).

grab_stats(Port) ->
    port_command(Port, <<0:32/native>>),
    {recv_data(Port), grab_local_stats()}.

grab_local_stats() ->
    #{cgroup_mem => memory_quota:cgroup_memory_data(),
      cpu_count => misc:cpu_count()}.

process_stats(TS, Binary, PrevSample, State) ->
    {{Stats0, ProcStats}, NewPrevSample} = unpack_data(Binary, PrevSample,
                                                       State),
    RetStats =
        case Stats0 of
            undefined ->
                [];
            _ ->
                case ets:update_counter(ns_server_system_stats, log_counter,
                                        {2, 1, ?ETS_LOG_INTVL, 0}) of
                    0 ->
                        log_system_stats(TS);
                    _ ->
                        ok
                end,
                [{"@system", Stats0}]
        end ++
        case ProcStats of
            undefined ->
                [];
            _ ->
                [{"@system-processes", ProcStats}]
        end,

    update_merger_rates(),
    sample_ns_memcached_queues(),
    {RetStats, NewPrevSample}.

increment_counter(Name) ->
    increment_counter(Name, 1).

increment_counter(Name, By) ->
    try
        do_increment_counter(Name, By)
    catch
        _:_ ->
            ok
    end.

do_increment_counter(Name, By) ->
    ets:insert_new(ns_server_system_stats, {Name, 0}),
    ets:update_counter(ns_server_system_stats, Name, By).

set_counter(Name, Value) ->
    (catch do_set_counter(Name, Value)).

do_set_counter(Name, Value) ->
    case ets:insert_new(ns_server_system_stats, {Name, Value}) of
        false ->
            ets:update_element(ns_server_system_stats, Name, {2, Value});
        true ->
            ok
    end.

get_ns_server_stats() ->
    ets:tab2list(ns_server_system_stats).

%% those constants are used to average config merger rates
%% exponentially. See
%% http://en.wikipedia.org/wiki/Moving_average#Exponential_moving_average
-define(TEN_SEC_ALPHA, 0.0951625819640405).
-define(MIN_ALPHA, 0.0165285461783825).
-define(FIVE_MIN_ALPHA, 0.0799555853706767).

combine_avg_key(Key, Prefix) ->
    case is_tuple(Key) of
        true ->
            list_to_tuple([Prefix | tuple_to_list(Key)]);
        false ->
            {Prefix, Key}
    end.

update_avgs(Key, Value) ->
    [update_avg(combine_avg_key(Key, Prefix), Value, Alpha)
     || {Prefix, Alpha} <- [{avg_10s, ?TEN_SEC_ALPHA},
                            {avg_1m, ?MIN_ALPHA},
                            {avg_5m, ?FIVE_MIN_ALPHA}]],
    ok.

update_avg(Key, Value, Alpha) ->
    OldValue = case ets:lookup(ns_server_system_stats, Key) of
                   [] ->
                       0;
                   [{_, V}] ->
                       V
               end,
    NewValue = OldValue + (Value - OldValue) * Alpha,
    set_counter(Key, NewValue).

read_counter(Key) ->
    ets:insert_new(ns_server_system_stats, {Key, 0}),
    [{_, V}] = ets:lookup(ns_server_system_stats, Key),
    V.

read_and_dec_counter(Key) ->
    V = read_counter(Key),
    increment_counter(Key, -V),
    V.

update_merger_rates() ->
    SleepTime = read_and_dec_counter(total_config_merger_sleep_time),
    update_avgs(config_merger_sleep_time, SleepTime),

    RunTime = read_and_dec_counter(total_config_merger_run_time),
    update_avgs(config_merger_run_time, RunTime),

    Runs = read_and_dec_counter(total_config_merger_runs),
    update_avgs(config_merger_runs_rate, Runs),

    QL = read_counter(config_merger_queue_len),
    update_avgs(config_merger_queue_len, QL).

just_avg_counter(RawKey, AvgKey) ->
    V = read_and_dec_counter(RawKey),
    update_avgs(AvgKey, V).

just_avg_counter(RawKey) ->
    just_avg_counter(RawKey, RawKey).

sample_ns_memcached_queues() ->
    KnownsServices = case ets:lookup(ns_server_system_stats,
                                     tracked_ns_memcacheds) of
                         [] -> [];
                         [{_, V}] -> V
                     end,
    Registered = [atom_to_list(Name) || Name <- registered()],
    ActualServices = [ServiceName ||
                      ("ns_memcached-" ++ _) = ServiceName <- Registered],
    ets:insert(ns_server_system_stats, {tracked_ns_memcacheds, ActualServices}),
    [begin
         [ets:delete(ns_server_system_stats, {Prefix, S, Stat})
          || Prefix <- [avg_10s, avg_1m, avg_5m]],
         ets:delete(ns_server_system_stats, {S, Stat})
     end
     || S <- KnownsServices -- ActualServices,
        Stat <- [qlen, call_time, calls, calls_rate,
                 long_call_time, long_calls, long_calls_rate,
                 e2e_call_time, e2e_calls, e2e_calls_rate]],
    [begin
         case (catch erlang:process_info(whereis(list_to_atom(S)),
                                         message_queue_len)) of
             {message_queue_len, QL} ->
                 QLenKey = {S, qlen},
                 update_avgs(QLenKey, QL),
                 set_counter(QLenKey, QL);
             _ -> ok
         end,

         just_avg_counter({S, call_time}),
         just_avg_counter({S, calls}, {S, calls_rate}),

         just_avg_counter({S, long_call_time}),
         just_avg_counter({S, long_calls}, {S, long_calls_rate}),

         just_avg_counter({S, e2e_call_time}),
         just_avg_counter({S, e2e_calls}, {S, e2e_calls_rate})
     end || S <- ["unknown" | ActualServices]],
    ok.

get_histo_bin(Value) when Value =< 0 -> 0;
get_histo_bin(Value) when Value > 64000000 -> infinity;
get_histo_bin(Value) when Value > 32000000 -> 64000000;
get_histo_bin(Value) when Value > 16000000 -> 32000000;
get_histo_bin(Value) when Value > 8000000 -> 16000000;
get_histo_bin(Value) when Value > 4000000 -> 8000000;
get_histo_bin(Value) when Value > 2000000 -> 4000000;
get_histo_bin(Value) when Value > 1000000 -> 2000000;
get_histo_bin(Value) ->
    Step = if
               Value < 100 -> 10;
               Value < 1000 -> 100;
               Value < 10000 -> 1000;
               Value =< 1000000 -> 10000
           end,
    ((Value + Step - 1) div Step) * Step.


-define(EPOCH_DURATION, 30).
-define(EPOCH_PRESERVE_COUNT, 5).

add_histo(Type, Value) ->
    BinV = get_histo_bin(Value),
    Epoch = erlang:monotonic_time(second) div ?EPOCH_DURATION,
    K = {h, Type, Epoch, BinV},
    increment_counter(K, 1),
    increment_counter({hg, Type, BinV}, 1).

cleanup_stale_epoch_histos() ->
    NowEpoch = erlang:monotonic_time(second) div ?EPOCH_DURATION,
    FirstStaleEpoch = NowEpoch - ?EPOCH_PRESERVE_COUNT,
    RV = ets:select_delete(ns_server_system_stats,
                           [{{{h, '_', '$1', '_'}, '_'},
                             [{'=<', '$1', {const, FirstStaleEpoch}}],
                             [true]}]),
    RV.

stale_histo_epoch_cleaner() ->
    erlang:register(system_stats_collector_stale_epoch_cleaner, self()),
    stale_histo_epoch_cleaner_loop().

stale_histo_epoch_cleaner_loop() ->
    cleanup_stale_epoch_histos(),
    timer:sleep(?EPOCH_DURATION * ?EPOCH_PRESERVE_COUNT * 1100),
    stale_histo_epoch_cleaner_loop().

spawn_ale_stats_collector() ->
    ns_pubsub:subscribe_link(
      ale_stats_events,
      fun ({{ale_disk_sink, Name}, StatName, Value}) ->
              add_histo({Name, StatName}, Value);
          (_) ->
              ok
      end).

grab_pid_names() ->
    OurPid = list_to_integer(os:getpid()),
    BabysitterPid = ns_server:get_babysitter_pid(),
    CouchdbPid = ns_couchdb_api:get_pid(),

    [{OurPid, <<"ns_server">>},
     {BabysitterPid, <<"babysitter">>},
     {CouchdbPid, <<"couchdb">>}].

adjust_process_name(Pid, Name, #state{pid_names = PidNames}) ->
    case lists:keyfind(Pid, 1, PidNames) of
        false ->
            Name;
        {Pid, BetterName} ->
            BetterName
    end.

compute_cpu_stats(OldCounters, Counters) ->
    Diffs = maps:map(fun (Key, Value) ->
                             OldValue = maps:get(Key, OldCounters),
                             Value - OldValue
                     end, Counters),

    #{cpu_idle_ms := Idle,
      cpu_user_ms := User,
      cpu_sys_ms := Sys,
      cpu_irq_ms := Irq,
      cpu_stolen_ms := Stolen,
      cpu_total_ms := Total} = Diffs,

    [{cpu_utilization_rate, compute_utilization(Total - Idle, Total)},
     {cpu_user_rate, compute_utilization(User, Total)},
     {cpu_sys_rate, compute_utilization(Sys, Total)},
     {cpu_irq_rate, compute_utilization(Irq, Total)},
     {cpu_stolen_rate, compute_utilization(Stolen, Total)}].

compute_utilization(Used, Total) ->
    try
        100 * Used / Total
    catch error:badarith ->
            0
    end.

-define(WIDTH, 30).

log_stats(TS, Bucket, RawStats) ->
    %% TS is epoch _milli_seconds
    TSMicros = (TS rem 1000) * 1000,
    TSSec0 = TS div 1000,
    TSMega = TSSec0 div 1000000,
    TSSec = TSSec0 rem 1000000,
    ?stats_debug("(at ~p (~p)) Stats for bucket ~p:~n~s",
                 [calendar:now_to_local_time({TSMega, TSSec, TSMicros}),
                  TS,
                  Bucket, format_stats(RawStats)]).

format_stats(Stats) ->
    erlang:list_to_binary(
      [case couch_util:to_binary(K0) of
           K -> [K, lists:duplicate(erlang:max(1, ?WIDTH - byte_size(K)), $\s),
                 couch_util:to_binary(V), $\n]
       end || {K0, V} <- lists:sort(Stats)]).

get_histogram_bucket(V, Max) when V > Max -> -1;
get_histogram_bucket(0, _Max) -> 0;
get_histogram_bucket(V, _Max) when is_integer(V) -> ceil(math:log10(V)).

to_seconds(Value, second) -> Value;
to_seconds(Value, millisecond) -> Value / 1000;
to_seconds(Value, microsecond) -> Value / 1000000.

normalized_metric(N) when is_atom(N); is_binary(N) ->
    normalized_metric({N, []});
normalized_metric({N, L}) when is_atom(N) ->
    normalized_metric({atom_to_binary(N, latin1), L});
normalized_metric({N, L}) when is_binary(N), is_list(L) ->
    {N, lists:usort(L)}.

notify_moving_window(F, Metric, Window, BucketSize, Now, Table, Val) ->
    Key = {mw, F, Window, normalized_metric(Metric)},
    Bucket = (Now div BucketSize) * BucketSize,
    try ets:lookup(Table, Key) of
        [] ->
            Q = queue:from_list([{Bucket, new_moving_window_bucket(F, Val)}]),
            catch ets:insert(Table, {Key, Q});
        [{Key, Q}] ->
            Q2 = prune_buckets(Now - Window, Q),
            Q3 = case queue:out(Q2) of
                     {{value, {Bucket, PrevVal}}, TmpQ} ->
                         NewVal = update_moving_window_bucket(F, PrevVal, Val),
                         queue:in_r({Bucket, NewVal}, TmpQ);
                     {_, _} ->
                         queue:in_r({Bucket, Val}, Q2)
                 end,
            catch ets:insert(Table, {Key, Q3}),
            ok
    catch
        error:badarg -> ok
    end.

new_moving_window_bucket(max, Val) -> Val.

update_moving_window_bucket(max, PrevVal, NewVal) ->
    case NewVal > PrevVal of
        true -> NewVal;
        false -> PrevVal
    end.

aggregate_moving_window_buckets(max, []) -> undefined;
aggregate_moving_window_buckets(max, Values) -> lists:max(Values).

prune_buckets(Deadline, Q) ->
    case queue:out_r(Q) of
        {{value, {TS, _}}, Q2} when TS < Deadline ->
            prune_buckets(Deadline, Q2);
        {_, _}  -> Q
    end.

-ifdef(TEST).

notify_moving_window_test() ->
    Tid = ets:new(test_table, [public, set]),
    try
        Buckets =
            fun () ->
                [{_, Q}] = ets:lookup(Tid, {mw, max, 1000, {<<"m">>, []}}),
                queue:to_list(Q)
            end,
        notify_moving_window(max, m, 1000, 100, 200, Tid, 3),
        notify_moving_window(max, m, 1000, 100, 250, Tid, 4),
        notify_moving_window(max, m, 1000, 100, 250, Tid, 2),
        notify_moving_window(max, m, 1000, 100, 255, Tid, 1),
        ?assertEqual([{200, 4}], Buckets()),
        notify_moving_window(max, m, 1000, 100, 400, Tid, 30),
        notify_moving_window(max, m, 1000, 100, 450, Tid, 40),
        notify_moving_window(max, m, 1000, 100, 455, Tid, 10),
        ?assertEqual([{400, 40}, {200, 4}], Buckets()),
        notify_moving_window(max, m, 1000, 100, 1201, Tid, 30),
        notify_moving_window(max, m, 1000, 100, 1300, Tid, 40),
        notify_moving_window(max, m, 1000, 100, 1350, Tid, 10),
        ?assertEqual([{1300, 40}, {1200, 30}, {400, 40}], Buckets()),
        notify_moving_window(max, m, 1000, 100, 2380, Tid, 11),
        ?assertEqual([{2300, 11}], Buckets())
    after
        ets:delete(Tid)
    end.

-endif.
