%% -*- erlang-indent-level: 4;indent-tabs-mode: nil; fill-column: 92 -*-
%% ex: ts=4 sw=4 et
%% @author Tyler Cloke <tyler@chef.io>
%% @copyright 2015 Chef Software, Inc.
%%
%% This migration sets up a global group called global-admins.
%% It also grants READ and CREATE permissions on the users container
%% to the global-admins group.
%%
-module(mover_global_installation_admins_callback).

-export([
         migration_init/0,
         migration_complete/0,
         migration_type/0,
         supervisor/0,
         migration_start_worker_args/2,
         migration_action/2,
         next_object/0,
         error_halts_migration/0,
         reconfigure_object/2,
         needs_account_dets/0
        ]).

-include("mover.hrl").
-include("mv_oc_chef_authz.hrl").

-define(GLOBAL_PLACEHOLDER_ORG_ID, <<"00000000000000000000000000000000">>).

-record(container, {authz_id}).
-record(mover_chef_group, {
          id,
          org_id,	  
          authz_id,
          name,
          last_updated_by,
          created_at,
          updated_at
         }).


migration_init() ->
    mv_oc_chef_authz_http:create_pool(),
    mover_transient_migration_queue:initialize_queue(?MODULE, [?GLOBAL_PLACEHOLDER_ORG_ID]).

migration_action(GlobalOrgId, _AcctInfo) ->
    SuperuserAuthzId = mv_oc_chef_authz:superuser_id(),                              
    GlobalAdminAuthzId = case create_global_admins_authz_group(SuperuserAuthzId) of
        AuthzId when is_binary(AuthzId) ->
            AuthzId;
        AuthzError ->
            lager:error("Could not create new authz group for global-admins."),
            throw(AuthzError)
    end,
    
    case create_global_admins_global_group(GlobalAdminAuthzId, GlobalOrgId) of
        {chef_sql, {GroupError, _}} ->
	    lager:error("Could not create new erchef group for global-admins."),
            throw(GroupError);
	_ -> true
    end,
    
    UserContainerAuthzId = get_user_container_authz_id(),
    case oc_chef_authz:add_ace_for_entity(SuperuserAuthzId,
                                          group, GlobalAdminAuthzId,
                                          container, UserContainerAuthzId,
                                          read) of
        {error, ReadAceError} ->
	    lager:error("Could not add READ ace to users container for global-admins."),
            throw(ReadAceError);
        _ -> true
    end,

    case oc_chef_authz:add_ace_for_entity(SuperuserAuthzId,
                                          group, GlobalAdminAuthzId,
                                          container, UserContainerAuthzId,
                                          create) of
        {error, CreateAceError} ->
	    lager:error("Could not add READ ace to users container for global-admins."),
            throw(CreateAceError);
        _ -> true
    end.

create_global_admins_authz_group(SuperuserAuthzId) ->
    case mv_oc_chef_authz:create_resource(SuperuserAuthzId, group) of
        {ok, AuthzId} ->
            AuthzId;
        {error, _} = Error ->
            Error
    end.

get_user_container_authz_id() ->
    {ok, [Container]} = sqerl:select(users_container_query(), [], rows_as_records, [container, record_info(fields, container)]),
    Container#container.authz_id.

users_container_query() ->
    <<"SELECT authz_id FROM containers WHERE name='users'">>.

create_global_admins_global_group(GlobalAdminAuthzId, GlobalOrgId) ->
    RequestorId = mv_oc_chef_authz:superuser_id(),                                                      
    Object = new_group_record(GlobalOrgId, GlobalAdminAuthzId, <<"global-admins">>, RequestorId),
    create_insert(Object, GlobalAdminAuthzId, RequestorId).

insert_group_sql() ->
    <<"INSERT INTO groups (id, org_id, authz_id, name,"
      " last_updated_by, created_at, updated_at) VALUES"
      " ($1, $2, $3, $4, $5, $6, $7)">>.

new_group_record(OrgId, AuthzId, Name, RequestorId) ->
    Now = os:timestamp(),
    Id = chef_object_base_make_org_prefix_id(OrgId, Name),
    #mover_chef_group{id = Id,
                      authz_id = AuthzId,
                      org_id = OrgId,
                      name = Name,
                      last_updated_by = RequestorId,
                      created_at = Now,
                      updated_at = Now}.

chef_object_flatten_group(ObjectRec) ->
    [_RecName|Tail] = tuple_to_list(ObjectRec),
    %% We detect if any of the fields in the record have not been set
    %% and throw an error
    case lists:any(fun is_undefined/1, Tail) of
        true -> error({undefined_in_record, ObjectRec});
        false -> ok
    end,
    Tail.

is_undefined(undefined) ->
    true;
is_undefined(_) ->
    false.

create_insert(#mover_chef_group{} = Object, AuthzId, _RequestorId) ->
    case chef_sql_create_group(chef_object_flatten_group(Object)) of
        {ok, 1} ->
            AuthzId;
        Error ->
            {chef_sql, {Error, Object}}
    end.

chef_sql_create_group(Args) ->
    sqerl:execute(insert_group_sql(), Args).

%% vendored from chef_object_base
chef_object_base_make_org_prefix_id(OrgId, Name) ->
    %% assume couchdb guid where trailing part has uniqueness
    <<_:20/binary, OrgSuffix:12/binary>> = OrgId,
    Bin = iolist_to_binary([OrgId, Name, crypto:rand_bytes(6)]),
    <<ObjectPart:80, _/binary>> = crypto:hash(md5, Bin),
    iolist_to_binary(io_lib:format("~s~20.16.0b", [OrgSuffix, ObjectPart])).

migration_complete() ->
    mv_oc_chef_authz_http:delete_pool().
%%
%% Generic mover callback functions for
%% a transient queue migration
%%
needs_account_dets() ->
    false.

migration_start_worker_args(Object, AcctInfo) ->
    [Object, AcctInfo].

next_object() ->
    mover_transient_migration_queue:next(?MODULE).

migration_type() ->
    <<"global_installation_admins">>.

supervisor() ->
    mover_transient_worker_sup.

error_halts_migration() ->
    false.

reconfigure_object(_ObjectId, _AcctInfo) ->
    ok.
