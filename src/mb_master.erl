%% @author Couchbase <info@couchbase.com>
%% @copyright 2010-Present Couchbase, Inc.
%%
%% Use of this software is governed by the Business Source License included
%% in the file licenses/BSL-Couchbase.txt.  As of the Change Date specified
%% in that file, in accordance with the Business Source License, use of this
%% software will be governed by the Apache License, Version 2.0, included in
%% the file licenses/APL2.txt.
%%
-module(mb_master).

-behaviour(gen_statem).

-compile({nowarn_deprecated_function, [{gen_fsm,send_event,2}]}).
-compile({nowarn_deprecated_function, [{gen_fsm,sync_send_all_state_event,3}]}).

-include("cut.hrl").
-include("ns_common.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

%% Constants and definitions
-define(HEARTBEAT_INTERVAL, ?get_param(heartbeat_interval, 2000)).
-define(TIMEOUT_INTERVAL_COUNT, ?get_param(timeout_interval_count, 5)).
-define(TIMEOUT, ?HEARTBEAT_INTERVAL * ?TIMEOUT_INTERVAL_COUNT).

-type node_info() :: {version(), node()}.

-record(state, {child :: undefined | pid(),
                master :: node(),
                peers :: [node()],
                last_heard :: integer(),
                higher_priority_nodes = [] :: [{node(), integer()}]}).


%% API
-export([start_link/0,
         master_node/0]).


%% gen_statem callbacks
-export([code_change/4,
         init/1,
         callback_mode/0,
         terminate/3]).

%% States
-export([candidate/3,
         master/3]).

%%
%% API
%%

start_link() ->
    maybe_invalidate_current_master(),
    gen_statem:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @doc Returns the master node for the cluster, or undefined if it's
%% not known yet.
master_node() ->
    gen_statem:call(?MODULE, master_node).

%% Returns the master node according to Node. For mb_master's internal use
%% only.
master_node(Node, Timeout) ->
    case cluster_compat_mode:is_cluster_65() of
        true ->
            gen_statem:call({?MODULE, Node}, master_node, Timeout);
        false ->
            gen_fsm:sync_send_all_state_event({?MODULE, Node},
                                              master_node, Timeout)
    end.

%%
%% gen_statem handlers
%%

callback_mode() ->
    state_functions.

init([]) ->
    chronicle_compat_events:notify_if_key_changes([nodes_wanted],
                                                  peers_changed),
    erlang:process_flag(trap_exit, true),
    CurHBInterval = ?HEARTBEAT_INTERVAL,
    ?log_debug("Heartbeat interval is ~p", [CurHBInterval]),
    send_heartbeat_msg(CurHBInterval),
    Now = erlang:monotonic_time(),
    case ns_node_disco:nodes_wanted() of
        [N] = P when N == node() ->
            ale:info(?USER_LOGGER, "I'm the only node, so I'm the master.", []),
            {ok, master, start_master(#state{last_heard=Now, peers=P})};
        Peers when is_list(Peers) ->
            %% We're a candidate
            ?log_debug("Starting as candidate. Peers: ~p", [Peers]),
            {ok, candidate, #state{last_heard = Now,
                                   %% Prevent new node from becoming master by
                                   %% accident, and wait for TIMEOUT amount of
                                   %% time before making a decision.
                                   higher_priority_nodes = [{node(), Now}],
                                   peers = Peers}}
    end.

maybe_invalidate_current_master() ->
    do_maybe_invalidate_current_master(3, true).

do_maybe_invalidate_current_master(0, _FirstTime) ->
    ale:error(?USER_LOGGER, "We're out of luck taking mastership over older node", []),
    ok;
do_maybe_invalidate_current_master(TriesLeft, FirstTime) ->
    NodesWantedActual = ns_node_disco:nodes_actual(),
    case check_master_takeover_needed(NodesWantedActual -- [node()]) of
        false ->
            case FirstTime of
                true -> ok;
                false ->
                    ale:warn(?USER_LOGGER, "Decided not to forcefully take over mastership", [])
            end,
            ok;
        {MasterToShutdown, Version} ->
            case do_invalidate_master(MasterToShutdown, Version) of
                ok ->
                    ok;
                retry ->
                    do_maybe_invalidate_current_master(TriesLeft-1, false);
                {error, Error} ->
                    ale:error(?USER_LOGGER,
                              "Failed to forcefully take mastership "
                              "over old node (~p): ~p",
                              [MasterToShutdown, Error])
            end
    end.

do_invalidate_master(MasterToShutdown, Version) ->
    WorkAroundMB33750 = should_workaround_mb33750(Version),
    SyncTimeout = case WorkAroundMB33750 of
                      true ->
                          %% If the old master is indeed affected by MB-33750,
                          %% the sync_surrender/2 call below will take a long
                          %% time because mb_master will be busy waiting for
                          %% mb_master_sup to terminate once we tell it to
                          %% surrender. The shutdown timeout is set to 10
                          %% seconds. So we need to use a timeout that will
                          %% give mb_master enough time to get unblocked.
                          20000;
                      false ->
                          5000
                  end,

    %% send our config to this master it doesn't make sure
    %% mb_master will see us in peers because of a couple of
    %% races, but at least we'll delay a bit on some work and
    %% increase chance of it. We'll retry if it's not the case
    ok = chronicle_compat:config_sync(push, [MasterToShutdown]),
    %% ask master to give up
    send_heartbeat_with_peers([MasterToShutdown],
                              master, [node(), MasterToShutdown]),
    %% sync that "surrender" event
    case sync_surrender(MasterToShutdown, SyncTimeout) of
        {ok, NewMaster} ->
            if NewMaster =:= node() ->
                    case WorkAroundMB33750 of
                        true ->
                            workaround_mb33750(MasterToShutdown, Version);
                        false ->
                            ok
                    end,
                    ok;
               NewMaster =:= MasterToShutdown ->
                    retry;
               true ->
                    {error, {unexpected_master, NewMaster}}
            end;
        Error ->
            Error
    end.

sync_surrender(MasterToShutdown, Timeout) ->
    try master_node(MasterToShutdown, Timeout) of
        Node ->
            {ok, Node}
    catch
        T:E ->
            {error, {T, E}}
    end.

%% Checks if a workaround for MB-33750 should be attempted. Will return true
%% if:
%%
%% - The old master is of the affected version.
%%
%% - The workaround is not explicitly disabled through an ns_config knob.
should_workaround_mb33750(Version) ->
    Enabled = ?get_param(mb33750_workaround_enabled, true),
    Affected = (Version >= [6, 0, 0]) andalso (Version < [6, 0, 2]),
    Enabled andalso Affected.

-define(stringify(Body), ??Body).

%% Applies a workaround for MB-33750 to the Node.
%%
%% The gist of the issue.
%%
%% The old master might fail to terminate leader_lease_acquirer after
%% surrendering mastership. If that happens, the old master will continue
%% actively acquiring leases disrupting the operation of the true master. The
%% workaround is to explicitly attempt to kill the leader_lease_acquirer
%% process on the old master. The details of the bug are such that killing the
%% leader_lease_acquirer might not kill its children. And it's those children
%% that are actually responsible for lease acquisitions. But it should at
%% least eventually kill those of them that can be killed. The rest of them
%% will get stuck in the shutdown sequence. So they are going to continue to
%% waste memory, but at least they won't be able to disrupt the operation of
%% the new master anymore.
workaround_mb33750(Node, Version) ->
    ?log_info("Going to attempt to kill leader_lease_acquirer "
              "on ~p (node version is ~p) as a workaround for MB-33750.",
              [Node, Version]),

    %% Can't simply "send" an anonymous function to another node, since it
    %% won't exist there. So we need to send the workaround as a string
    %% payload to misc:eval/2 instead.
    EvalPayload =
        ?stringify(begin
                       Pid = whereis(leader_lease_acquirer),
                       case is_pid(Pid) andalso is_process_alive(Pid) of
                           true ->
                               exit(Pid, kill),
                               killed;
                           false ->
                               not_found
                       end
                   end),
    EvalBindings = erl_eval:new_bindings(),

    case call_eval(Node, EvalPayload, EvalBindings) of
        {ok, killed} ->
            ?log_info("Applied the workaround for MB-33750 on ~p. "
                      "Actually found lingering leader_lease_acquirer.",
                      [Node]);
        {ok, not_found} ->
            ?log_info("Applied the workaround for MB-33750 on ~p. "
                      "No lingering leader_lease_acquirer found.",
                      [Node]);
        Other ->
            ?log_info("Failed to apply the workaround for "
                      "MB-33750 on ~p. Return value: ~p", [Node, Other])
    end.

call_eval(Node, Payload, Bindings) ->
    case rpc:call(Node, misc, eval, [Payload, Bindings], 10000) of
        {value, Result, _} ->
            {ok, Result};
        Error ->
            Error
    end.

check_master_takeover_needed(Peers) ->
    TenNodesToAsk = lists:sublist(misc:shuffle(Peers), 10),
    ?log_debug("Sending master node question to the following nodes: ~p", [TenNodesToAsk]),
    {MasterReplies, _} = rpc:multicall(TenNodesToAsk, mb_master, master_node, [], 5000),
    ?log_debug("Got replies: ~p", [MasterReplies]),
    GoodMasterReplies = [M || M <- MasterReplies,
                              M =/= undefined,
                              is_atom(M)],
    case GoodMasterReplies of
        [] ->
            ?log_debug("Was unable to discover master, not going to force mastership takeover"),
            false;
        [Master|_] when Master =:= node() ->
            %% assuming it happens only secound round
            ale:warn(?USER_LOGGER, "Somebody thinks we're master. Not forcing mastership takover over ourselves"),
            false;
        [Master|_] ->
            ?log_debug("Checking version of current master: ~p", [Master]),
            case rpc:call(Master, cluster_compat_mode, mb_master_advertised_version, [], 5000) of
                {badrpc, _} = Error ->
                    ale:warn(?USER_LOGGER,
                             "Failed to grab master's version. "
                             "Assuming force mastership "
                             "takeover is not needed. Reason: ~p", [Error]),
                    false;
                CompatVersion ->
                    ?log_debug("Current master's supported compat version: ~p", [CompatVersion]),
                    MasterNodeInfo = build_node_info(CompatVersion, Master),
                    case strongly_lower_priority_node(MasterNodeInfo) of
                        true ->
                            ale:warn(?USER_LOGGER, "Current master is older and I'll try to takeover", []),
                            {Master, CompatVersion};
                        false ->
                            ?log_debug("Current master is not older"),
                            false
                    end
            end
    end.

code_change(_OldVsn, StateName, StateData, _Extra) ->
    {ok, StateName, StateData}.


terminate(_Reason, _StateName, StateData) ->
    case StateData of
        #state{child=Child} when is_pid(Child) ->
            ?log_info("Synchronously shutting down child mb_master_sup"),
            shutdown_master_sup(StateData);
        _ ->
            ok
    end.


%%
%% States
%%

candidate(info, peers_changed, StateData) ->
    Peers = ns_node_disco:nodes_wanted(),
    S = refresh_high_priority_nodes(update_peers(StateData, Peers)),
    case Peers of
        [N] when N == node() ->
            ale:info(?USER_LOGGER, "I'm now the only node, so I'm the master.", []),
            {next_state, master, start_master(S)};
        _ ->
            case can_be_master(S) of
                true ->
                    ale:info(?USER_LOGGER,
                             "Master has been removed from cluster. "
                             "I'm taking over as the master.", []),
                    {next_state, master, start_master(S)};
                false ->
                    {keep_state, S}
            end
    end;
candidate(info, {send_heartbeat, LastHBInterval},
          #state{peers=Peers} = StateData) ->
    StartTS = erlang:monotonic_time(),

    MostOfTimeout = ?TIMEOUT * 4 div 5,

    Armed = diag_handler:arm_timeout(MostOfTimeout),
    send_heartbeat_msg(LastHBInterval),
    send_heartbeat_with_peers(Peers, candidate, Peers),
    diag_handler:disarm_timeout(Armed),

    SpentOnSending = erlang:convert_time_unit(erlang:monotonic_time() - StartTS,
                                              native, millisecond),

    SinceHeard  = erlang:convert_time_unit(StartTS - StateData#state.last_heard,
                                           native, millisecond),

    case SinceHeard >= ?TIMEOUT andalso SpentOnSending < MostOfTimeout of
        true ->
            %% Take over
            ale:info(?USER_LOGGER, "Haven't heard from a higher priority node or "
                     "a master, so I'm taking over.", []),
            {next_state, master, start_master(StateData)};
        false ->
            keep_state_and_data
    end;
candidate(info, {heartbeat, NodeInfo, master, _H},
          #state{peers=Peers} = State) ->
    Node = node_info_to_node(NodeInfo),

    case lists:member(Node, Peers) of
        false ->
            ?log_warning("Candidate got master heartbeat from node ~p "
                         "which is not in peers ~p", [Node, Peers]),
            keep_state_and_data;
        true ->
            %% If master is of strongly lower priority than we are, then we send fake
            %% mastership hertbeat to force previous master to surrender. Thus
            %% there will be some time when cluster won't have any master
            %% node. But after timeout mastership will be taken over by the
            %% node with highest priority.
            NewState =
                case strongly_lower_priority_node(NodeInfo) of
                    false ->
                        Now = erlang:monotonic_time(),
                        update_high_priority_nodes(
                          {Node, Now}, State#state{last_heard = Now,
                                                   master = Node});
                    true ->
                        case rebalance:status() of
                            running ->
                                ale:info(?USER_LOGGER,
                                         "Candidate got master heartbeat from "
                                         "node ~p which has lower priority. "
                                         "But I won't try to take over since "
                                         "rebalance seems to be running",
                                         [Node]),
                                State#state{last_heard=erlang:monotonic_time(), master=Node};
                            _ ->
                                ale:info(?USER_LOGGER,
                                         "Candidate got master heartbeat from "
                                         "node ~p which has lower priority. "
                                         "Will try to take over.", [Node]),

                                send_heartbeat_with_peers([Node], master, State#state.peers),
                                State#state{master=undefined}
                        end
                end,

            OldMaster = State#state.master,
            NewMaster = NewState#state.master,
            case OldMaster =:= NewMaster of
                true ->
                    ok;
                false ->
                    ?log_info("Changing master from ~p to ~p",
                              [OldMaster, NewMaster]),
                    announce_leader(NewMaster)
            end,
            {keep_state, NewState}
    end;

candidate(info, {heartbeat, NodeInfo, candidate, _H},
          #state{peers=Peers} = State) ->
    Node = node_info_to_node(NodeInfo),

    case lists:member(Node, Peers) of
        true ->
            case higher_priority_node(NodeInfo) of
                true ->
                    Now = erlang:monotonic_time(),
                    %% Higher priority node
                    {keep_state, update_high_priority_nodes(
                                   {Node, Now},
                                   State#state{last_heard = Now})};
                false ->
                    %% Lower priority, so ignore it
                    keep_state_and_data
            end;
        false ->
            ?log_warning("Candidate got candidate heartbeat from node ~p which "
                         "is not in peers ~p", [Node, Peers]),
            keep_state_and_data

    end;

candidate(Type, Msg, State) ->
    handle_event(Type, Msg, candidate, State).

master(info, peers_changed, StateData) ->
    Peers = ns_node_disco:nodes_wanted(),
    S = refresh_high_priority_nodes(update_peers(StateData, Peers)),
    case lists:member(node(), Peers) of
        true ->
            {keep_state, S};
        false ->
            ?log_info("Master has been demoted. Peers = ~p", [Peers]),
            NewState = shutdown_master_sup(S),
            {next_state, candidate, NewState}
    end;
master(info, {send_heartbeat, LastHBInterval}, StateData) ->
    send_heartbeat_msg(LastHBInterval),
    send_heartbeat_with_peers(ns_node_disco:nodes_wanted(), master, StateData#state.peers),
    keep_state_and_data;
master(info, {heartbeat, NodeInfo, master, _H}, #state{peers=Peers} = State) ->
    Node = node_info_to_node(NodeInfo),

    case lists:member(Node, Peers) of
        true ->
            Now = erlang:monotonic_time(),

            case higher_priority_node(NodeInfo) of
                true ->
                    ?log_info("Surrendering mastership to ~p", [Node]),
                    NewState = shutdown_master_sup(State),
                    announce_leader(Node),
                    {next_state, candidate,
                     update_high_priority_nodes(
                       {Node, Now},
                       NewState#state{last_heard = Now,
                                      master = Node})};
                false ->
                    ?log_info("Got master heartbeat from ~p when I'm master",
                              [Node]),
                    {keep_state, State#state{last_heard=Now}}
            end;
        false ->
            ?log_warning("Master got master heartbeat from node ~p which is "
                         "not in peers ~p", [Node, Peers]),
            keep_state_and_data
    end;

master(info, {heartbeat, NodeInfo, candidate, _H}, #state{peers=Peers} = State) ->
    Node = node_info_to_node(NodeInfo),

    case lists:member(Node, Peers) of
        true ->
            ok;
        false ->
            ?log_warning("Master got candidate heartbeat from node ~p which is "
                         "not in peers ~p", [Node, Peers])
    end,
    {keep_state, State#state{last_heard=erlang:monotonic_time()}};

master(Type, Msg, State) ->
    handle_event(Type, Msg, master, State).

handle_event(info, {'EXIT', _From, Reason} = Msg, _, _) ->
    ?log_info("Dying because of linked process exit: ~p~n", [Msg]),
    exit(Reason);
handle_event({call, From}, master_node, _State, StateData) ->
    {keep_state_and_data, [{reply, From, StateData#state.master}]};
%% Backward compitibility: handle heartbeats from nodes that are older than
%%                         6.5 where gen_fsm is running
handle_event(info, {'$gen_event', Event}, _State, _StateData) ->
    {keep_state_and_data, [{next_event, info, Event}]};
handle_event(Type, Msg, State, StateData) ->
    ?log_warning("Got unexpected event ~p of type ~p in state ~p with data ~p",
                 [Msg, Type, State, StateData]),
    keep_state_and_data.

%%
%% Internal functions
%%

%% @private
%% @doc Send an heartbeat to a list of nodes, except this one.
send_heartbeat_with_peers(Nodes, StateName, Peers) ->
    NodeInfo = node_info(),

    Args = {heartbeat, NodeInfo, StateName,
            [{peers, Peers},
             {versioning, true}]},
    try
        %% we try to avoid sending event to nodes that are
        %% down. Because send call inside gen_fsm will try to
        %% establish connection each time we try to send.
        %% + also exclude local node here
        AliveNodes = lists:filter(lists:member(_, nodes()), Nodes),
        Is65 = cluster_compat_mode:is_cluster_65(),
        misc:parallel_map(
          fun (Node) when Is65 ->
                  catch erlang:send({?MODULE, Node}, Args, [noconnect]);
              (Node) ->
                  gen_fsm:send_event({?MODULE, Node}, Args)
          end, AliveNodes, 2000),
        ok
    catch exit:timeout ->
              ?log_warning("send heartbeat timed out")
    end.


%% @private
%% @doc Go into master state. Returns new state data.
start_master(StateData) ->
    announce_leader(node()),
    {ok, Pid} = mb_master_sup:start_link(),
    StateData#state{child = Pid,
                    master = node(),
                    higher_priority_nodes = []}.


%% @private
%% @doc Update the list of peers in the state. Also logs when it
%% changes.
update_peers(StateData, Peers) ->
    O = lists:sort(StateData#state.peers),
    P = lists:sort(Peers),
    case O == P of
        true ->
            %% No change
            StateData;
        false ->
            ?log_debug("List of peers has changed from ~p to ~p", [O, P]),
            StateData#state{peers=P}
    end.

shutdown_master_sup(State) ->
    Pid = State#state.child,
    misc:unlink_terminate_and_wait(Pid, shutdown),
    announce_leader(undefined),
    State#state{child = undefined,
                master = undefined}.


%% Auxiliary functions

build_node_info(CompatVersion, Node) ->
    VersionStruct = {CompatVersion, release, 0},
    {VersionStruct, Node}.

%% Return node information for ourselves.
-spec node_info() -> node_info().
node_info() ->
    Version = cluster_compat_mode:mb_master_advertised_version(),
    build_node_info(Version, node()).

%% Convert node info to node.
-spec node_info_to_node(node_info()) -> node().
node_info_to_node({_Version, Node}) ->
    Node.

%% Determine whether some node is of higher priority than ourselves.
-spec higher_priority_node(node_info()) -> boolean().
higher_priority_node(NodeInfo) ->
    Self = node_info(),
    higher_priority_node(Self, NodeInfo).

higher_priority_node({SelfVersion, SelfNode},
                     {Version, Node}) ->
    if
        Version > SelfVersion ->
            true;
        Version =:= SelfVersion ->
            Node < SelfNode;
        true ->
            false
    end.

%% true iff we need to take over mastership of given node
-spec strongly_lower_priority_node(node_info()) -> boolean().
strongly_lower_priority_node(NodeInfo) ->
    Self = node_info(),
    strongly_lower_priority_node(Self, NodeInfo).

strongly_lower_priority_node({SelfVersion, _SelfNode},
                              {Version, _Node}) ->
    (Version < SelfVersion).

announce_leader(Node) ->
    gen_event:sync_notify(leader_events, {new_leader, Node}).

send_heartbeat_msg(LastHBInterval) ->
    CurHBInterval = ?HEARTBEAT_INTERVAL,
    case LastHBInterval =/= CurHBInterval of
        true ->
            ?log_debug("Heartbeat interval changed from ~p to ~p",
                       [LastHBInterval, CurHBInterval]);
        false ->
            ok
    end,

    erlang:send_after(CurHBInterval, self(), {send_heartbeat, CurHBInterval}).

can_be_master(#state{master = Master,
                     peers = Peers,
                     higher_priority_nodes = HigherPriorityNodes}) ->
    not lists:member(Master, Peers) andalso
        HigherPriorityNodes =:= [] andalso
        lists:member(node(), Peers).

update_high_priority_nodes({Node, Now},
                           #state{higher_priority_nodes = Nodes} = State) ->
    NewNodes = lists:keystore(Node, 1, Nodes, {Node, Now}),
    State#state{higher_priority_nodes = NewNodes}.

refresh_high_priority_nodes(#state{higher_priority_nodes = Nodes,
                                   peers = Peers} = State) ->
    Now = erlang:monotonic_time(),
    NewNodes = lists:filter(
                 fun ({N, LastSeen}) ->
                         SinceHeard  = erlang:convert_time_unit(
                                         Now - LastSeen,
                                         native, millisecond),
                         SinceHeard < ?TIMEOUT andalso
                             (lists:member(N, Peers) orelse

                              %% This forces the a newly initialized node to
                              %% wait for TIMEOUT before it can become the
                              %% master. Don't clear it we are not part of the
                              %% cluster yet.
                              N =:= node())
                 end, Nodes),
    State#state{higher_priority_nodes = NewNodes}.

-ifdef(TEST).
priority_test() ->
    ?assertEqual(true,
                 higher_priority_node({misc:parse_version("1.7.1"),
                                       'ns_1@192.168.1.1'},
                                      {misc:parse_version("2.0"),
                                       'ns_2@192.168.1.1'})),
    ?assertEqual(true,
                 higher_priority_node({misc:parse_version("1.7.1"),
                                       'ns_2@192.168.1.1'},
                                      {misc:parse_version("2.0"),
                                       'ns_1@192.168.1.1'})),
    ?assertEqual(false,
                 higher_priority_node({misc:parse_version("2.0"),
                                       'ns_1@192.168.1.1'},
                                      {misc:parse_version("1.7.2"),
                                       'ns_0@192.168.1.1'})),
    ?assertEqual(true, higher_priority_node({misc:parse_version("2.0"),
                                             'ns_2@192.168.1.1'},
                                            {misc:parse_version("2.0"),
                                             'ns_1@192.168.1.1'})).
-endif.
