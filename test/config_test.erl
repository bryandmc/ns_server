% Copyright (c) 2008, Cliff Moon
% Copyright (c) 2008, Powerset, Inc
% Copyright (c) 2009, NorthScale, Inc
%
% All rights reserved.
%
% Redistribution and use in source and binary forms, with or without
% modification, are permitted provided that the following conditions
% are met:
%
% * Redistributions of source code must retain the above copyright
% notice, this list of conditions and the following disclaimer.
% * Redistributions in binary form must reproduce the above copyright
% notice, this list of conditions and the following disclaimer in the
% documentation and/or other materials provided with the distribution.
% * Neither the name of Powerset, Inc nor the names of its
% contributors may be used to endorse or promote products derived from
% this software without specific prior written permission.
%
% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
% "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
% LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
% FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
% COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
% INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
% BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
% LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
% CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
% LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
% ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
% POSSIBILITY OF SUCH DAMAGE.
%
% Original Author: Cliff Moon

-include_lib("eunit/include/eunit.hrl").

-compile(export_all).

all_test_() ->
  {foreach,
    fun() -> test_setup() end,
    fun(V) -> test_teardown(V) end,
  [
    {"test_search_list",
     ?_test(test_search_list())},
    {"test_search_config",
     ?_test(test_search_config())},
    {"test_merge_config_static",
     ?_test(test_merge_config_static())},
    {"test_merge_config_dynamic",
     ?_test(test_merge_config_dynamic())},
    {"test_persist",
     ?_test(test_persist())}
  ]}.

test_search_list() ->
    ?assertMatch(false, search([], foo)),
    ?assertMatch(false, search([[], []], foo)),
    ?assertMatch(false, search([[{x, 1}]], foo)),
    ?assertMatch({value, 1}, search([[{x, 1}], [{x, 2}]], x)),
    ok.

test_search_config() ->
    ?assertMatch(false,
                 search(#config{},
                        x)),
    ?assertMatch(false,
                 search(#config{dynamic = [[], []],
                                static = [[], []]},
                        x)),
    ?assertMatch({value, 1},
                 search(#config{dynamic = [[{x, 1}], [{x, 2}]],
                                static = []},
                        x)),
    ?assertMatch({value, 2},
                 search(#config{dynamic = [[{y, 1}], [{x, 2}]],
                                static = [[], []]},
                        x)),
    ?assertMatch({value, 3},
                 search(#config{dynamic = [[{y, 1}], [{x, 2}]],
                                static = [[{w, 4}], [{z, 3}]]},
                        z)),
    ?assertMatch({value, 2},
                 search(#config{dynamic = [[{y, 1}], [{z, 2}]],
                                static = [[{w, 4}], [{z, 3}]]},
                        z)),
    ok.

test_merge_config_static() ->
    Mergable = [x, y, z, rx, lx],
    ?assertEqual(
       #config{},
       merge_configs(Mergable,
         #config{},
         #config{})),
    X0 = #config{dynamic = [],
                 static = []},
    ?assertEqual(X0,
       merge_configs(Mergable,
         #config{dynamic = [],
                 static = []},
         #config{dynamic = [],
                 static = []})),
    X1 = #config{dynamic = [[{x,1}]],
                 static = [[{x,1}]]},
    ?assertEqual(X1,
       merge_configs(Mergable,
         #config{dynamic = [],
                 static = []},
         #config{dynamic = [],
                 static = [[{x,1}]]})),
    X2 = #config{dynamic = [[{rx,1},{lx,1}]],
                 static = [[{lx,1}]]},
    ?assertEqual(X2,
       merge_configs(Mergable,
         #config{dynamic = [],
                 static = [[{rx,1}]]},
         #config{dynamic = [],
                 static = [[{lx,1}]]})),
    X3 = #config{dynamic = [[{lx,2}]],
                 static = [[{lx,1}]]},
    ?assertEqual(X3,
       merge_configs(Mergable,
         #config{dynamic = [],
                 static = [[{lx,2}]]},
         #config{dynamic = [],
                 static = [[{lx,1}]]})),
    X4 = #config{dynamic = [[{rx,1},{lx,1}]],
                 static = [[{lx,1},{foo,9}]]},
    ?assertEqual(X4,
       merge_configs(Mergable,
         #config{dynamic = [],
                 static = [[{rx,1},{lx,1},{foo,10}]]},
         #config{dynamic = [],
                 static = [[{lx,1},{foo,9}]]})),
    ok.

test_merge_config_dynamic() ->
    Mergable = [x, y, z],
    X0 = #config{dynamic = [[{x,1},{y,1}]],
                 static = [[{x,1}]]},
    ?assertEqual(X0,
       merge_configs(Mergable,
         #config{dynamic = [],
                 static = []},
         #config{dynamic = [[{y,1}]],
                 static = [[{x,1}]]})),
    X1 = #config{dynamic = [[{x,1},{y,1}]],
                 static = [[{x,1}]]},
    ?assertEqual(X1,
       merge_configs(Mergable,
         #config{dynamic = [[{y,1}]],
                 static = []},
         #config{dynamic = [],
                 static = [[{x,1}]]})),
    X2 = #config{dynamic = [[{x,1},{y,1}]],
                 static = [[{x,1},{foo,9}]]},
    ?assertEqual(X2,
       merge_configs(Mergable,
         #config{dynamic = [[{y,1}]],
                 static = []},
         #config{dynamic = [[{y,2}]],
                 static = [[{x,1},{foo,9}]]})),
    X3 = #config{dynamic = [[{x,1},{y,1}]],
                 static = [[{x,1},{foo,9}]]},
    ?assertEqual(X3,
       merge_configs(Mergable,
         #config{dynamic = [[{y,1}]],
                 static = [[{foo,10}]]},
         #config{dynamic = [[{y,2}]],
                 static = [[{x,1},{foo,9}]]})),
    ok.

test_persist() ->
    CP = data_file(),
    D = [[{x,1},{y,2},{z,3}]],
    ?assertEqual(ok, save_config(bin, CP, D)),
    R = load_config(bin, CP),
    ?assertEqual({ok, D}, R),
    ok.

test_setup() ->
    ok.

test_teardown(_) ->
    file:delete(data_file()),
    ok.

priv_dir() ->
  Dir = filename:join([t:config(priv_dir), "data", "config"]),
  filelib:ensure_dir(filename:join(Dir, "config")),
  Dir.

data_file()     -> data_file(atom_to_list(node())).
data_file(Name) -> filename:join([priv_dir(), Name]).
