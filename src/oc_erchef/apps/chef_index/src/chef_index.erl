%% Copyright 2015 Chef Software, Inc
%%
%% This file is provided to you under the Apache License,
%% Version 2.0 (the "License"); you may not use this file
%% except in compliance with the License.  You may obtain
%% a copy of the License at
%%
%%   http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing,
%% software distributed under the License is distributed on an
%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%% KIND, either express or implied.  See the License for the
%% specific language governing permissions and limitations
%% under the License.
%%

-module(chef_index).

-export([delete/3,
         add/4]).

add(TypeName, Id, DbName, IndexEjson) ->
    case envy:get(chef_index, disable_rabbitmq, false, boolean) of
        false ->
            ok = chef_index_queue:set(envy:get(chef_index, rabbitmq_vhost, binary), TypeName, Id, DbName, IndexEjson);
        true ->
            Pid = pooler:take_member(chef_index_expand),
            TypeName2 = case TypeName of
                            data_bag_item ->
                                ej:get({<<"data_bag">>}, IndexEjson);
                            T ->
                                T
                        end,
            chef_index_expand:init_items(Pid, 1),
            chef_index_expand:add_item(Pid, Id, IndexEjson, TypeName2, DbName),
            chef_index_expand:send_items(Pid),
            pooler:return_member(chef_index_expand, Pid)
    end.

delete(TypeName, Id, DbName) ->
    case envy:get(chef_index, disable_rabbitmq, false, boolean) of
        false ->
            ok = chef_index_queue:delete(envy:get(chef_index, rabbitmq_vhost, binary), TypeName, Id, DbName);
        true ->
            Pid = pooler:take_member(chef_index_expand),
            chef_index_expand:init_items(Pid, 1),
            chef_index_expand:delete_item(Pid, Id, TypeName, DbName),
            chef_index_expand:send_items(Pid),
            pooler:return_member(chef_index_expand, Pid)
    end.
