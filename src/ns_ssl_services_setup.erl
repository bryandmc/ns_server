%% @author Couchbase <info@couchbase.com>
%% @copyright 2013-Present Couchbase, Inc.
%%
%% Use of this software is governed by the Business Source License included
%% in the file licenses/BSL-Couchbase.txt.  As of the Change Date specified
%% in that file, in accordance with the Business Source License, use of this
%% software will be governed by the Apache License, Version 2.0, included in
%% the file licenses/APL2.txt.

-module(ns_ssl_services_setup).

-include("ns_common.hrl").
-include_lib("public_key/include/public_key.hrl").
-include("cut.hrl").

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

-export([start_link/0,
         start_link_capi_service/0,
         start_link_rest_service/0,
         pkey_file_path/0,
         chain_file_path/0,
         ca_file_path/0,
         legacy_cert_path/0,
         sync/0,
         ssl_minimum_protocol/1,
         ssl_minimum_protocol/2,
         client_cert_auth/0,
         client_cert_auth_state/0,
         client_cert_auth_state/1,
         get_user_name_from_client_cert/1,
         set_node_certificate_chain/4,
         ssl_client_opts/0,
         configured_ciphers_names/2,
         honor_cipher_order/1,
         honor_cipher_order/2,
         set_certs/4,
         chronicle_upgrade_to_NEO/1,
         unencrypted_pkey_file_path/0,
         remove_node_certs/0]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

%% exported for debugging purposes
-export([low_security_ciphers/0]).

-import(couch_httpd, [make_arity_1_fun/1,
                      make_arity_2_fun/1,
                      make_arity_3_fun/1]).

-behavior(gen_server).

-record(state, {reload_state,
                client_cert_auth,
                sec_settings_state,
                afamily_requirement}).

start_link() ->
    case cluster_compat_mode:tls_supported() of
        true ->
            gen_server:start_link({local, ?MODULE}, ?MODULE, [], []);
        false ->
            ignore
    end.

start_link_capi_service() ->
    ok = ns_couchdb_config_rep:pull(),
    case service_ports:get_port(ssl_capi_port, ns_config:latest(),
                                ns_node_disco:ns_server_node()) of
        undefined ->
            ignore;
        SSLPort ->
            do_start_link_capi_service(SSLPort)
    end.

do_start_link_capi_service(SSLPort) ->
    ok = ssl:clear_pem_cache(),

    Options = [{port, SSLPort},
               {ssl, true},
               {ssl_opts, ssl_server_opts()},
               {ip, misc:inaddr_any()}],

    %% the following is copied almost verbatim from couch_httpd.  The
    %% difference is that we don't touch "ssl" key of couch config and
    %% that we don't register on config changes.
    %%
    %% Not touching ssl key is important because otherwise main capi
    %% http service will restart itself. And I decided it's better to
    %% localize capi code here for now rather than change somewhat
    %% fossilized couchdb code.
    %%
    %% Also couchdb code is reformatted for ns_server formatting
    DefaultSpec = "{couch_httpd_db, handle_request}",
    DefaultFun = make_arity_1_fun(
                   couch_config:get("httpd", "default_handler", DefaultSpec)),

    UrlHandlersList =
        lists:map(
          fun({UrlKey, SpecStr}) ->
                  {list_to_binary(UrlKey), make_arity_1_fun(SpecStr)}
          end, couch_config:get("httpd_global_handlers")),

    DbUrlHandlersList =
        lists:map(
          fun({UrlKey, SpecStr}) ->
                  {list_to_binary(UrlKey), make_arity_2_fun(SpecStr)}
          end, couch_config:get("httpd_db_handlers")),

    DesignUrlHandlersList =
        lists:map(
          fun({UrlKey, SpecStr}) ->
                  {list_to_binary(UrlKey), make_arity_3_fun(SpecStr)}
          end, couch_config:get("httpd_design_handlers")),

    UrlHandlers = dict:from_list(UrlHandlersList),
    DbUrlHandlers = dict:from_list(DbUrlHandlersList),
    DesignUrlHandlers = dict:from_list(DesignUrlHandlersList),
    {ok, ServerOptions} = couch_util:parse_term(
                            couch_config:get("httpd", "server_options", "[]")),
    {ok, SocketOptions} = couch_util:parse_term(
                            couch_config:get("httpd", "socket_options", "[]")),

    DbFrontendModule = list_to_atom(couch_config:get("httpd", "db_frontend", "couch_db_frontend")),

    ExtraHeaders = menelaus_util:compute_sec_headers(),

    Loop =
        fun(Req)->
                case SocketOptions of
                    [] ->
                        ok;
                    _ ->
                        ok = mochiweb_socket:setopts(mochiweb_request:get(socket, Req), SocketOptions)
                end,
                apply(couch_httpd, handle_request,
                      [Req, DbFrontendModule, DefaultFun, UrlHandlers,
                       DbUrlHandlers, DesignUrlHandlers, ExtraHeaders])
        end,

    %% set mochiweb options
    FinalOptions = lists:append([Options, ServerOptions,
                                 [{loop, Loop},
                                  {name, https}]]),

    %% launch mochiweb
    {ok, _Pid} = case mochiweb_http:start(FinalOptions) of
                     {ok, MochiPid} ->
                         {ok, MochiPid};
                     {error, Reason} ->
                         io:format("Failure to start Mochiweb: ~s~n",[Reason]),
                         throw({error, Reason})
                 end.

%% generated using "openssl dhparam -outform DER 2048"
dh_params_der() ->
    <<48,130,1,8,2,130,1,1,0,152,202,99,248,92,201,35,238,246,
      5,77,93,120,10,118,129,36,52,111,193,167,220,49,229,106,
      105,152,133,121,157,73,158,232,153,197,197,21,171,140,
      30,207,52,165,45,8,221,162,21,199,183,66,211,247,51,224,
      102,214,190,130,96,253,218,193,35,43,139,145,89,200,250,
      145,92,50,80,134,135,188,205,254,148,122,136,237,220,
      186,147,187,104,159,36,147,217,117,74,35,163,145,249,
      175,242,18,221,124,54,140,16,246,169,84,252,45,47,99,
      136,30,60,189,203,61,86,225,117,255,4,91,46,110,167,173,
      106,51,65,10,248,94,225,223,73,40,232,140,26,11,67,170,
      118,190,67,31,127,233,39,68,88,132,171,224,62,187,207,
      160,189,209,101,74,8,205,174,146,173,80,105,144,246,25,
      153,86,36,24,178,163,64,202,221,95,184,110,244,32,226,
      217,34,55,188,230,55,16,216,247,173,246,139,76,187,66,
      211,159,17,46,20,18,48,80,27,250,96,189,29,214,234,241,
      34,69,254,147,103,220,133,40,164,84,8,44,241,61,164,151,
      9,135,41,60,75,4,202,133,173,72,6,69,167,89,112,174,40,
      229,171,2,1,2>>.

supported_versions(MinVer) ->
    case application:get_env(ssl_versions) of
        {ok, Versions} ->
            Versions;
        undefined ->
            Patches = proplists:get_value(couchbase_patches,
                                          ssl:versions(), []),
            Versions0 = ['tlsv1.1', 'tlsv1.2',  'tlsv1.3'],

            Versions1 = case lists:member(tls_padding_check, Patches) of
                            true ->
                                ['tlsv1' | Versions0];
                            false ->
                                Versions0
                        end,
            case lists:dropwhile(fun (Ver) -> Ver < MinVer end, Versions1) of
                [] ->
                    ?log_warning("Incorrect ssl_minimum_protocol ~p was ignored.", [MinVer]),
                    Versions1;
                Versions ->
                    Versions
            end
    end.

ssl_minimum_protocol(Service) ->
    ssl_minimum_protocol(Service, ns_config:latest()).

ssl_minimum_protocol(Service, Config) ->
    get_sec_setting(Service, ssl_minimum_protocol, Config, 'tlsv1.2').


get_sec_setting(Service, Setting, Config, Default) ->
    case ns_config:search_prop(Config, {security_settings, Service}, Setting) of
        undefined ->
            ns_config:search(Config, Setting, Default);
        Val ->
            Val
    end.

client_cert_auth(Cfg) ->
    DefaultValue = [{state, "disable"}, {prefixes, []}],
    ns_config:search(Cfg, client_cert_auth, DefaultValue).

client_cert_auth() ->
    client_cert_auth(ns_config:latest()).

client_cert_auth_state(Cfg) ->
    proplists:get_value(state, client_cert_auth(Cfg)).

client_cert_auth_state() ->
    client_cert_auth_state(ns_config:latest()).

%% The list is obtained by running the following openssl command:
%%
%%   openssl ciphers LOW:RC4 | tr ':' '\n'
%%
low_security_ciphers_openssl() ->
    ["EDH-RSA-DES-CBC-SHA",
     "EDH-DSS-DES-CBC-SHA",
     "DH-RSA-DES-CBC-SHA",
     "DH-DSS-DES-CBC-SHA",
     "ADH-DES-CBC-SHA",
     "DES-CBC-SHA",
     "DES-CBC-MD5",
     "ECDHE-RSA-RC4-SHA",
     "ECDHE-ECDSA-RC4-SHA",
     "AECDH-RC4-SHA",
     "ADH-RC4-MD5",
     "ECDH-RSA-RC4-SHA",
     "ECDH-ECDSA-RC4-SHA",
     "RC4-SHA",
     "RC4-MD5",
     "RC4-MD5",
     "PSK-RC4-SHA",
     "EXP-ADH-RC4-MD5",
     "EXP-RC4-MD5",
     "EXP-RC4-MD5"].

openssl_cipher_to_erlang(Cipher) ->
    try ssl_cipher_format:suite_legacy(
          ssl_cipher_format:suite_openssl_str_to_map(Cipher)) of
        V ->
            {ok, V}
    catch _:_ ->
            %% erlang is bad at reporting errors here; on R16B03 it just fails
            %% with function_clause error so I need to catch all here
            {error, unsupported}
    end.

low_security_ciphers() ->
    Ciphers = low_security_ciphers_openssl(),
    [EC || C <- Ciphers, {ok, EC} <- [openssl_cipher_to_erlang(C)]].

ns_server_ciphers() ->
    Config = ns_config:latest(),
    case configured_ciphers(ns_server, Config) of
        [] ->
            %% Backward compatibility
            %% ssl_ciphers is obsolete and should not be used in
            %% new installations
            case application:get_env(ssl_ciphers) of
                {ok, Ciphers} -> Ciphers;
                undefined -> ciphers:backwards_compatible_ciphers()
                                 -- low_security_ciphers()
            end;
        List -> List
    end.

configured_ciphers_names(Service, Config) ->
    ciphers:only_known(get_sec_setting(Service, cipher_suites, Config, [])).

configured_ciphers(Service, Config) ->
    [ciphers:code(N) || N <- configured_ciphers_names(Service, Config)].


honor_cipher_order(Service) -> honor_cipher_order(Service, ns_config:latest()).
honor_cipher_order(Service, Config) ->
    get_sec_setting(Service, honor_cipher_order, Config, true).

ssl_auth_options() ->
    Val = list_to_atom(proplists:get_value(state, client_cert_auth())),
    case Val of
        disable ->
            [];
        enable ->
            [{verify, verify_peer}, {depth, ?ALLOWED_CERT_CHAIN_LENGTH}];
        mandatory ->
            [{fail_if_no_peer_cert, true},
             {verify, verify_peer}, {depth, ?ALLOWED_CERT_CHAIN_LENGTH}]
    end.

ssl_server_opts() ->
    PassphraseFun =
        case ns_node_disco:couchdb_node() == node() of
            true ->
                rpc:call(ns_node_disco:ns_server_node(), ns_secrets,
                         get_pkey_pass, []);
            false ->
                ns_secrets:get_pkey_pass()
        end,
    CipherSuites = ns_server_ciphers(),
    Order = honor_cipher_order(ns_server),
    ClientReneg = ns_config:read_key_fast(client_renegotiation_allowed, false),
    OtpVersion = erlang:list_to_integer(erlang:system_info(otp_release)),
    %% Pass CA as cacerts opt (instead of cacertfile) in order to
    %% work around unknown bug in erlang ssl application that leads to
    %% the following behavior:
    %% web server doesn't load new CA (after cert rotation) until
    %% all connections to the server are closed
    ssl_auth_options() ++
        [{keyfile, pkey_file_path()},
         %% It should be chain_file_path() for erl >= 23
         {certfile, cert_file_path(OtpVersion)},
         {versions, supported_versions(ssl_minimum_protocol(ns_server))},
         %% It should be just ca_file_path() for erl >= 23
         {cacerts, read_ca_certs(ca_file_path(OtpVersion))},
         {dh, dh_params_der()},
         {ciphers, CipherSuites},
         {honor_cipher_order, Order},
         {secure_renegotiate, true},
         {client_renegotiation, ClientReneg},
         {password, PassphraseFun()}].

read_ca_certs(File) ->
    case file:read_file(File) of
        {ok, CAPemBin} ->
            {ok, Certs} = ns_server_cert:decode_cert_chain(CAPemBin),
            Certs;
        {error, enoent} ->
            []
    end.

ssl_client_opts() ->
    [{cacerts, ns_server_cert:trusted_CAs(der)},
     {verify, verify_peer},
     {depth, ?ALLOWED_CERT_CHAIN_LENGTH}].

start_link_rest_service() ->
    case service_ports:get_port(ssl_rest_port) of
        undefined ->
            ignore;
        SSLPort ->
            Config3 = [{ssl, true},
                       {name, menelaus_web_ssl},
                       {ssl_opts, ssl_server_opts()},
                       {port, SSLPort}],
            menelaus_web:start_link(Config3)
    end.

marker_path() ->
    filename:join(path_config:component_path(data, "config"), "reload_marker").

ca_file_path() ->
    ca_file_path_erl23_plus().

ca_file_path(OtpVersion) when OtpVersion >= 23 ->
    ca_file_path_erl23_plus();
ca_file_path(OtpVersion) when OtpVersion < 23 ->
    ca_file_path_erl22().

cert_file_path(OtpVersion) when OtpVersion >= 23 ->
    chain_file_path();
cert_file_path(OtpVersion) when OtpVersion < 23 ->
    cert_file_path_erl22().

ca_file_path_erl23_plus() ->
    filename:join(path_config:component_path(data, "config"), "ca.pem").
chain_file_path() ->
    filename:join(path_config:component_path(data, "config"), "chain.pem").
pkey_file_path() ->
    filename:join(path_config:component_path(data, "config"), "pkey.pem").
tmp_certs_and_key_file() ->
    filename:join(path_config:component_path(data, "config"), "certs.tmp").
cert_info_file() ->
    filename:join(path_config:component_path(data, "config"), "certs.info").

ca_file_path_erl22() ->
    filename:join(path_config:component_path(data, "config"), "ca_erl22.pem").
cert_file_path_erl22() ->
    filename:join(path_config:component_path(data, "config"), "cert_erl22.pem").
legacy_cert_path() ->
    filename:join(path_config:component_path(data, "config"), "legacy_cert.pem").
unencrypted_pkey_file_path() ->
    filename:join(path_config:component_path(data, "config"), "unencrypted_pkey.pem").

sync() ->
    chronicle_compat_events:sync(),
    %% First ping guarantees that async_ssl_reload has sent
    %% the notify_services message
    ok = gen_server:call(?MODULE, ping, infinity),
    %% Second ping guarantees that the notify_services message message
    %% has been handled
    ok = gen_server:call(?MODULE, ping, infinity).

set_node_certificate_chain(CAEntry, Chain, PKey, PassphraseSettings) ->
    gen_server:call(?MODULE, {set_node_certificate_chain, CAEntry, Chain, PKey,
                              PassphraseSettings}, infinity).

set_certs(Host, CA, NodeCert, NodeKey) ->
    gen_server:call(?MODULE, {set_certs, Host, CA, NodeCert, NodeKey}).

init([]) ->
    Self = self(),
    chronicle_compat_events:subscribe(handle_config_change(_, Self)),

    maybe_convert_pre_NEO_certs(),
    _ = save_node_certs_phase2(),
    maybe_store_ca_certs(),
    maybe_generate_node_certs(),
    RetrySvc = case misc:marker_exists(marker_path()) of
                   true ->
                       %% In case if we crashed in the middle of certs
                       %% generation. It should do nothing if "auto-generated"
                       %% certs are in order.
                       Self ! notify_services,
                       all_services() -- [ssl_service];
                   false ->
                       []
               end,
    {ok, #state{reload_state = RetrySvc,
                sec_settings_state = security_settings_state(),
                afamily_requirement = misc:address_family_requirement(),
                client_cert_auth = client_cert_auth()}}.

handle_config_change(ca_certificates, Parent) ->
    Parent ! ca_certificates_updated;
handle_config_change(cert_and_pkey, Parent) ->
    Parent ! cert_and_pkey_changed;
%% we're using this key to detect change of node() name
handle_config_change({node, _Node, capi_port}, Parent) ->
    Parent ! cert_and_pkey_changed;
handle_config_change(ssl_minimum_protocol, Parent) ->
    Parent ! security_settings_changed;
handle_config_change(client_cert_auth, Parent) ->
    Parent ! client_cert_auth_changed;
handle_config_change(cipher_suites, Parent) ->
    Parent ! security_settings_changed;
handle_config_change(honor_cipher_order, Parent) ->
    Parent ! security_settings_changed;
handle_config_change(secure_headers, Parent) ->
    Parent ! secure_headers_changed;
handle_config_change({security_settings, ns_server}, Parent) ->
    Parent ! security_settings_changed;
handle_config_change({node, _Node, address_family}, Parent) ->
    Parent ! afamily_requirement_changed;
handle_config_change({node, _Node, address_family_only}, Parent) ->
    Parent ! afamily_requirement_changed;
handle_config_change(cluster_compat_version, Parent) ->
    Parent ! ca_certificates_updated;
handle_config_change(_OtherEvent, _Parent) ->
    ok.


handle_call({set_node_certificate_chain, CAEntry, Chain, PKey,
             PassphraseSettings}, _From, State) ->
    Props = save_uploaded_certs(CAEntry, Chain, PKey, PassphraseSettings),
    {reply, {ok, Props}, sync_ssl_reload(State)};

%% This is used in the case when this node is added to a cluster
%% and that cluster pushes generated node certs to us (only in the case when
%% certs are self-generated)
%% Note: During node addition this certificates are generated by another
%% cluster (by another CA)
handle_call({set_certs, Host, CA, NodeCert, NodeKey}, _From, State) ->
    ns_server_cert:set_generated_ca(CA),
    CAUpdated = maybe_store_ca_certs(),
    NodeCertUpdated =
        if
            (NodeCert =/= undefined) andalso (NodeKey =/= undefined) ->
                save_generated_certs(CA, NodeCert, NodeKey, Host),
                true;
            true ->
                ?log_warning("Set certs: Node certs are not present. Ignoring"),
                false
        end,
    case CAUpdated or NodeCertUpdated of
        true -> {reply, ok, sync_ssl_reload(State)};
        false -> {reply, ok, State}
    end;
handle_call(ping, _From, State) ->
    {reply, ok, State};
handle_call(_, _From, State) ->
    {reply, unknown_call, State}.

handle_cast(_, State) ->
    {noreply, State}.

handle_info(ca_certificates_updated, #state{} = State) ->
    misc:flush(ca_certificates_updated),
    case maybe_store_ca_certs() of
        true -> {noreply, sync_ssl_reload(State)};
        false -> {noreply, State}
    end;

%% It means either we generated new cluster CA cert or hostname changed
handle_info(cert_and_pkey_changed, #state{} = State) ->
    ?log_info("cert_and_pkey changed"),
    misc:flush(cert_and_pkey_changed),
    NeedReload =
        maybe_generate_node_certs() or
        case cluster_compat_mode:is_cluster_NEO() of
            true -> false;
            false -> maybe_store_ca_certs()
        end,
    case NeedReload of
        true -> {noreply, sync_ssl_reload(State)};
        false -> {noreply, State}
    end;

handle_info(afamily_requirement_changed,
            #state{afamily_requirement = Current} = State) ->
    misc:flush(afamily_requirement_changed),
    case misc:address_family_requirement() of
        Current ->
            {noreply, State};
        NewValue ->
            {noreply, async_ssl_reload(
                        address_family_requirement, [ssl_service],
                        State#state{afamily_requirement = NewValue})}
    end;
handle_info(security_settings_changed,
            #state{sec_settings_state = Current} = State) ->
    misc:flush(security_settings_changed),
    case security_settings_state() of
        Current ->
            {noreply, State};
        NewValue ->
            {noreply, async_ssl_reload(cipher_suites,
                                       [ssl_service, capi_ssl_service],
                                       State#state{
                                           sec_settings_state = NewValue})}
    end;
handle_info(client_cert_auth_changed,
            #state{client_cert_auth = Auth} = State) ->
    misc:flush(client_cert_auth_changed),
    case client_cert_auth() of
        Auth ->
            {noreply, State};
        Other ->
            {noreply, async_ssl_reload(client_cert_auth,
                                       [ssl_service, capi_ssl_service],
                                       State#state{client_cert_auth = Other})}
    end;
handle_info(secure_headers_changed, State) ->
    misc:flush(secure_headers_changed),
    {noreply, async_ssl_reload(secure_headers_changed, [capi_ssl_service],
                               State)};

handle_info(notify_services, State) ->
    misc:flush(notify_services),
    {noreply, notify_services(State)};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

prepare_ca_file_content() ->
    CAs = [string:trim(P) || P <- ns_server_cert:trusted_CAs(pem)],
    {length(CAs), iolist_to_binary(lists:join(io_lib:nl(), CAs))}.

maybe_store_ca_certs() ->
    %% just to trigger generation of ca cert if it's not generated yet
    _ = ns_server_cert:self_generated_ca(),
    {N, NewContent} = prepare_ca_file_content(),
    Path = ca_file_path(),

    ShouldUpdate =
        case file:read_file(Path) of
            {ok, NewContent} -> false;
            {ok, _} -> true;
            {error, enoent} -> true
        end,

    case ShouldUpdate of
        true ->
            ok = misc:atomic_write_file(Path, NewContent),
            ?log_info("CA file updated: ~b cert(s) written", [N]),
            %% Can be removed when upgraded to erl >= 23
            update_certs_erl22(),
            %% Can be removed when all the services and memcached switch to new
            %% cert format (where ca certs are kept separately)
            update_legacy_cert_file(),
            misc:create_marker(marker_path());
        false ->
            ok
    end,

    ShouldUpdate.

generated_cert_version(ClusterCA, Hostname) ->
    base64:encode(erlang:md5(term_to_binary({ClusterCA, Hostname}))).

maybe_generate_node_certs() ->
    Hostname = misc:extract_node_address(node()),
    %% We can't keep info for certs regeneration in node_cert key because during
    %% rename it may extract wrong info by wrong nodename from ns_config.
    %% Based on this wrong info it might decide to regenerate certs when it
    %% should not.
    ShouldGenerate =
        case file:consult(cert_info_file()) of
            {ok, [uploaded]} ->
                false;
            {ok, [{generated, OldVsn}]} ->
                ClusterCA = ns_server_cert:self_generated_ca(),
                case generated_cert_version(ClusterCA, Hostname) of
                    OldVsn -> false;
                    _ -> true
                end;
            {error, enoent} ->
                true
        end,
    case ShouldGenerate of
        true ->
            case ns_server_cert:generate_node_certs(Hostname) of
                no_private_key ->
                    ?log_warning("Node doesn't have private key, "
                                 "skipping node cert generation"),
                    false;
                {CA, CertChain, NodeKey} ->
                    save_generated_certs(CA, CertChain, NodeKey, Hostname),
                    true
            end;
        false ->
            false
    end.

async_ssl_reload(Event, Services, #state{reload_state = ReloadState} = State) ->
    misc:create_marker(marker_path()),
    self() ! notify_services,
    ?log_debug("Notify services ~p about ~p change", [Services, Event]),
    State#state{reload_state = lists:usort(Services ++ ReloadState)}.

sync_ssl_reload(State) ->
    NewState = State#state{reload_state = all_services()},
    notify_services(NewState).


save_generated_certs(CA, Chain, PKey, Hostname) ->
    save_node_certs(generated, CA, Chain, PKey, [], [{hostname, Hostname}]).
save_uploaded_certs(CA, Chain, PKey, PassphraseSettings) ->
    save_node_certs(uploaded, CA, Chain, PKey, PassphraseSettings, []).

%% CA, PKey and Chain are pem encoded
%% Chain :: [NodeCert, IntermediateCert, ...]
save_node_certs(Type, CA, Chain, PKey, PassphraseSettings, Extra)
                                                        when is_binary(CA),
                                                             is_binary(Chain),
                                                             is_binary(PKey) ->
    {Subject, Expiration} =
        ns_server_cert:get_chain_info(Chain, CA),
    UTCTime = calendar:universal_time(),
    LoadTime = calendar:datetime_to_gregorian_seconds(UTCTime),
    Props = [{subject, iolist_to_binary(Subject)},
             {not_after, Expiration},
             {verified_with, erlang:md5(CA)},
             {type, Type},
             {load_timestamp, LoadTime},
             {ca, CA},
             {pem, Chain},
             {pkey_passphrase_settings, PassphraseSettings} | Extra],

    Data = term_to_binary({node_certs, Props, Chain, PKey}),

    ok = misc:atomic_write_file(tmp_certs_and_key_file(), Data),
    ?log_info("New node cert and pkey are written to tmp file"),
    ok = save_node_certs_phase2(),
    Props.

save_node_certs_phase2() ->
    TmpFile = tmp_certs_and_key_file(),
    case file:read_file(TmpFile) of
        {ok, Bin} ->
            {node_certs, Props, Chain, PKey} = binary_to_term(Bin),
            ok = misc:atomic_write_file(chain_file_path(), Chain),
            ok = misc:atomic_write_file(pkey_file_path(), PKey),
            CertsInfo = case proplists:get_value(type, Props) of
                            generated ->
                                Host = proplists:get_value(hostname, Props),
                                CA = proplists:get_value(ca, Props),
                                {generated, generated_cert_version(CA, Host)};
                            uploaded ->
                                uploaded
                        end,
            CertsInfoBin = iolist_to_binary(io_lib:format("~p.", [CertsInfo])),
            ok = misc:atomic_write_file(cert_info_file(), CertsInfoBin),
            ?log_info("Node cert and pkey files updated"),
            %% Can be removed when upgraded to erl >= 23
            update_certs_erl22(),
            ns_config:set({node, node(), node_cert}, Props),
            %% Can be removed when all the services and memcached switch to new
            %% cert format (where ca certs are kept separately)
            update_legacy_cert_file(),
            update_legacy_unencrypted_key(Props), %% MUST BE REMOVED IN NEO
            ok = ssl:clear_pem_cache(),
            misc:create_marker(marker_path()),
            ok = file:delete(TmpFile);
        {error, enoent} -> file_not_found
    end.

update_certs_erl22() ->
    Erl22Chain =
        case file:read_file(chain_file_path()) of
            {ok, Chain} ->
                [NodeCertDecoded | ChainDecoded] = public_key:pem_decode(Chain),
                NodeCert = public_key:pem_encode([NodeCertDecoded]),
                misc:atomic_write_file(cert_file_path_erl22(), NodeCert),
                case ChainDecoded of
                    [] -> [];
                    _ -> [public_key:pem_encode(ChainDecoded)]
                end;
            {error, enoent} ->
                []
        end,
    CAs = case file:read_file(ca_file_path()) of
              {ok, C} -> [C];
              {error, enoent} -> []
          end,
    Erl22CAs = lists:join(io_lib:nl(), Erl22Chain ++ CAs),
    misc:atomic_write_file(ca_file_path_erl22(), Erl22CAs).

update_legacy_cert_file() ->
    Chain = case file:read_file(chain_file_path()) of
                {ok, C} -> [C];
                {error, enoent} -> []
            end,
    CA = case ns_config:search({node, node(), node_cert}) of
             {value, Props} -> [proplists:get_value(ca, Props)];
             false -> []
         end,
    LegacyCert = lists:join(io_lib:nl(), Chain ++ CA),
    misc:atomic_write_file(legacy_cert_path(), LegacyCert).

update_legacy_unencrypted_key(Props) ->
    Settings = proplists:get_value(pkey_passphrase_settings, Props, []),
    PassphraseFun = ns_secrets:get_pkey_pass(Settings),
    {ok, B} = file:read_file(pkey_file_path()),
    File = unencrypted_pkey_file_path(),
    case public_key:pem_decode(B) of
        [{_, _, not_encrypted}] -> misc:atomic_write_file(File, B);
        [{ASNType, _, _} = Entry] ->
            DecodedEntry = public_key:pem_entry_decode(Entry, PassphraseFun()),
            Entry2 = public_key:pem_entry_encode(ASNType, DecodedEntry),
            misc:atomic_write_file(File, public_key:pem_encode([Entry2]))
    end.

-spec get_user_name_from_client_cert(term()) -> string() | undefined | failed.
get_user_name_from_client_cert(Val) ->
    ClientAuth = ns_ssl_services_setup:client_cert_auth(),
    {state, State} = lists:keyfind(state, 1, ClientAuth),
    case Val of
        {ssl, SSLSock} ->
            case {ssl:peercert(SSLSock), State} of
                {_, "disable"} ->
                    undefined;
                {{ok, Cert}, _} ->
                    get_user_name_from_client_cert(Cert, ClientAuth);
                {{error, no_peercert}, "enable"} ->
                    undefined;
                {{error, R}, _} ->
                    ?log_debug("Error getting client certificate: ~p",
                               [R]),
                    failed
            end;
        Cert when is_binary(Cert) ->
            get_user_name_from_client_cert(Cert, ClientAuth);
        _ ->
            undefined
    end.

get_user_name_from_client_cert(Cert, ClientAuth) ->
    Triples = proplists:get_value(prefixes, ClientAuth),
    case get_user_name_from_client_cert_inner(Cert, Triples) of
        {error, _} ->
            failed;
        Username ->
            Username
    end.

get_user_name_from_client_cert_inner(_Cert, []) ->
    {error, not_found};
get_user_name_from_client_cert_inner(Cert, [Triple | Rest]) ->
    {path, Path} = lists:keyfind(path, 1, Triple),
    [Category, Field] = string:tokens(Path, "."),
    case get_fields_from_cert(Cert, Category, Field) of
        {error, _} ->
            get_user_name_from_client_cert_inner(Cert, Rest);
        Values ->
            Prefix = proplists:get_value(prefix, Triple),
            Delimiters = proplists:get_value(delimiter, Triple),
            case extract_user_name(Values, Prefix, Delimiters) of
                {error, _} ->
                    get_user_name_from_client_cert_inner(Cert, Rest);
                UName ->
                    UName
            end
    end.

get_fields_from_cert(Cert, "subject", "cn") ->
    ns_server_cert:get_subject_fields_by_type(Cert, ?'id-at-commonName');
get_fields_from_cert(Cert, "san", Field) ->
    Type = san_field_to_type(Field),
    ns_server_cert:get_sub_alt_names_by_type(Cert, Type).

extract_user_name([], _Prefix, _Delimiters) ->
    {error, not_found};
extract_user_name([Val | Rest], Prefix, Delimiters) ->
    case do_extract_user_name(Val, Prefix, Delimiters) of
        {error, not_found} ->
            extract_user_name(Rest, Prefix, Delimiters);
        Username ->
            Username
    end.

do_extract_user_name(Name, Prefix, Delimiters) ->
    Name1 = string:prefix(Name, Prefix),

    case Name1 of
        nomatch ->
            {error, not_found};
        _ ->
            lists:takewhile(fun(C) ->
                                    not lists:member(C, Delimiters)
                            end, Name1)
    end.

san_field_to_type("dnsname") -> dNSName;
san_field_to_type("uri") -> uniformResourceIdentifier;
san_field_to_type("email") -> rfc822Name.

all_services() ->
    [cb_dist_tls, ssl_service, capi_ssl_service, xdcr_proxy, memcached, event].

notify_services(#state{reload_state = []} = State) -> State;
notify_services(#state{reload_state = Reloads} = State) ->
    ?log_debug("Going to notify following services: ~p", [Reloads]),

    RVs = diag_handler:diagnosing_timeouts(
            fun () ->
                    misc:parallel_map(fun notify_service/1, Reloads, 60000)
            end),
    ResultPairs = lists:zip(RVs, Reloads),
    {Good, Bad} = lists:foldl(fun ({ok, Svc}, {AccGood, AccBad}) ->
                                      {[Svc | AccGood], AccBad};
                                  (ErrorPair, {AccGood, AccBad}) ->
                                      {AccGood, [ErrorPair | AccBad]}
                              end, {[], []}, ResultPairs),
    case Good of
        [] ->
            ok;
        _ ->
            ?log_info("Succesfully notified services ~p", [Good])
    end,
    case Bad of
        [] ->
            misc:remove_marker(marker_path()),
            ok;
        _ ->
            ?log_info("Failed to notify some services. Will retry in 5 sec, ~p", [Bad]),
            erlang:send_after(5000, self(), notify_services)
    end,
    State#state{reload_state = [Svc || {_, Svc} <- Bad]}.

notify_service(Service) ->
    RV = (catch do_notify_service(Service)),
    case RV of
        ok ->
            ?log_info("Successfully notified service ~p", [Service]);
        Other ->
            ?log_warning("Failed to notify service ~p: ~p", [Service, Other])
    end,

    RV.

do_notify_service(ssl_service) ->
    %% NOTE: We're going to talk to our supervisor so if we do it
    %% synchronously there's chance of deadlock if supervisor is about
    %% to shutdown us.
    %%
    %% We're not trapping exits and that makes this interaction safe.
    case ns_ssl_services_sup:restart_ssl_service() of
        ok ->
            ok;
        {error, not_running} ->
            ?log_info("Did not restart ssl rest service because it wasn't running"),
            ok
    end;
do_notify_service(capi_ssl_service) ->
    case ns_couchdb_api:restart_capi_ssl_service() of
        ok ->
            ok;
        {error, not_running} ->
            ?log_info("Did not restart capi ssl service because is wasn't running"),
            ok
    end;
do_notify_service(xdcr_proxy) ->
    ns_ports_setup:restart_xdcr_proxy();
do_notify_service(memcached) ->
    memcached_config_mgr:trigger_tls_config_push();
do_notify_service(event) ->
    gen_event:notify(ssl_service_events, cert_changed);
do_notify_service(cb_dist_tls) ->
    cb_dist:restart_tls().

security_settings_state() ->
    {ssl_minimum_protocol(ns_server),
     honor_cipher_order(ns_server),
     ns_server_ciphers()}.

-ifdef(TEST).
extract_user_name_test() ->
    ?assertEqual(extract_user_name(["www.abc.com"], "www.", ";,."), "abc"),
    ?assertEqual(extract_user_name(["xyz.abc.com", "qwerty", "www.abc.com"],
                                   "www.", "."), "abc"),
    ?assertEqual(extract_user_name(["xyz.com", "www.abc.com"], "", "."), "xyz"),
    ?assertEqual(extract_user_name(["abc", "xyz"], "", ""), "abc"),
    ?assertEqual(extract_user_name(["xyz.abc.com"],
                                   "www.", "."), {error, not_found}),
    ?assertEqual(extract_user_name(["xyz.abc.com"], "", "-"), "xyz.abc.com").
-endif.

maybe_convert_pre_NEO_certs() ->
    ShouldConvert = should_convert_pre_neo_certs(),

    case ShouldConvert of
        true ->
            ?log_info("Upgrading certs to NEO..."),
            {value, CertAndPKey} = ns_config:search(cert_and_pkey),
            Type =
                case CertAndPKey of
                    {_, _} -> generated;
                    {_, _, _} ->
                        case ns_config:search({node, node(), cert}) of
                            {value, _} -> uploaded;
                            false -> generated
                        end
                end,
            ?log_info("Certs type: ~p", [Type]),

            case Type of
                generated ->
                    CA = case CertAndPKey of
                             {_, P, _} -> P;
                             {P, _} -> P
                         end,
                    {ok, NodeCert} = file:read_file(local_cert_path()),
                    {ok, NodePKey} = file:read_file(local_pkey_path()),
                    Hostname = misc:extract_node_address(node()),
                    ?log_info("Saving the following chain~n~p", [NodeCert]),
                    _ = save_generated_certs(CA, NodeCert, NodePKey, Hostname);
                uploaded ->
                    %% Note: this user provided CA might be not the same as
                    %% in user provided CA cert in cert_and_pkey.
                    %% The CA cert from this file must be the one that
                    %% signed the node cert, while the CA cert
                    %% in cert_and_pkey might be different.
                    {ok, ChainWithCA} =
                        file:read_file(user_set_ca_chain_path()),
                    ?log_info("Orig chain: ~p", [ChainWithCA]),
                    [CADecoded | ChainTailReversedDecoded] =
                        lists:reverse(public_key:pem_decode(ChainWithCA)),
                    CA = public_key:pem_encode([CADecoded]),
                    {ok, NodeCert} = file:read_file(user_set_cert_path()),
                    ?log_info("Orig node cert: ~p", [ChainWithCA]),
                    ChainDecoded = public_key:pem_decode(NodeCert) ++
                                   lists:reverse(ChainTailReversedDecoded),
                    Chain = public_key:pem_encode(ChainDecoded),
                    {ok, NodePKey} = file:read_file(user_set_key_path()),
                    ?log_info("Saving the following chain~n~p", [Chain]),
                    _ = save_uploaded_certs(CA, Chain, NodePKey, [])
            end,

            FilesToRemove = pre_NEO_files_to_remove(),

            lists:foreach(
              fun (F) ->
                  R = file:delete(F),
                  ?log_warning("Removing file: ~s, result: ~p", [F, R])
              end, FilesToRemove),

            ?log_info("Certs upgraded"),
            ok;
        false ->
            ok
    end.

pre_NEO_files_to_remove() ->
    [raw_ssl_cacert_key_path(),
     ssl_cert_key_path(),
     memcached_cert_path(),
     memcached_key_path(),
     local_cert_path(),
     local_pkey_path(),
     local_cert_meta_path(),
     user_set_cert_path(),
     user_set_key_path(),
     user_set_ca_chain_path()].

should_convert_pre_neo_certs() ->
    case ns_config:read_key_fast({node, node(), node_cert}, undefined) of
        undefined ->
            lists:any(fun (P) -> filelib:is_file(P) end,
                      pre_NEO_files_to_remove());
        _ -> false
    end.

raw_ssl_cacert_key_path() ->
    ssl_cert_key_path() ++ "-ca".
ssl_cert_key_path() ->
    filename:join(path_config:component_path(data, "config"),
                  "ssl-cert-key.pem").
memcached_cert_path() ->
    filename:join(path_config:component_path(data, "config"),
                  "memcached-cert.pem").
memcached_key_path() ->
    filename:join(path_config:component_path(data, "config"),
                  "memcached-key.pem").

local_cert_path() ->
    local_cert_path_prefix() ++ "cert.pem".
local_pkey_path() ->
    local_cert_path_prefix() ++ "pkey.pem".
local_cert_meta_path() ->
    local_cert_path_prefix() ++ "meta".
local_cert_path_prefix() ->
    filename:join(path_config:component_path(data, "config"),
                  "local-ssl-").
user_set_cert_path() ->
    filename:join(path_config:component_path(data, "config"),
                  "user-set-cert.pem").
user_set_key_path() ->
    filename:join(path_config:component_path(data, "config"),
                  "user-set-key.pem").
user_set_ca_chain_path() ->
    filename:join(path_config:component_path(data, "config"),
                  "user-set-ca.pem").

chronicle_upgrade_to_NEO(ChronicleTxn) ->
    Props = ns_server_cert:trusted_CAs_pre_NEO(ns_config:get()),
    ?log_info("Upgrading CA certs to NEO: setting ca_certificates to the "
              "following props:~n ~p", [Props]),
    chronicle_upgrade:set_key(ca_certificates, Props, ChronicleTxn).

remove_node_certs() ->
    ?log_warning("Removing node certificate and private key"),
    file:delete(cert_info_file()),
    file:delete(chain_file_path()),
    file:delete(pkey_file_path()).
