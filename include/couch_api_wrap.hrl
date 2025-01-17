% Copyright 2013-Present Couchbase, Inc.
%
% Use of this software is governed by the Business Source License included in
% the file licenses/BSL-Couchbase.txt.  As of the Change Date specified in that
% file, in accordance with the Business Source License, use of this software
% will be governed by the Apache License, Version 2.0, included in the file
% licenses/APL2.txt.

% Licensed under the Apache License, Version 2.0 (the "License"); you may not
% use this file except in compliance with the License. You may obtain a copy of
% the License at
%
%   http://www.apache.org/licenses/LICENSE-2.0
%
% Unless required by applicable law or agreed to in writing, software
% distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
% WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
% License for the specific language governing permissions and limitations under
% the License.



-record(httpdb, {
    url,
    oauth = nil,
    headers = [
        {"Accept", "application/json"},
        {"User-Agent", "CouchDB/" ++ couch_server:get_version()}
    ],
    timeout,            % milliseconds
    lhttpc_options = [],
    retries = 10,
    wait = 250,         % milliseconds
    httpc_pool = nil,
    http_connections
}).

-record(oauth, {
    consumer_key,
    token,
    token_secret,
    consumer_secret,
    signature_method
}).
