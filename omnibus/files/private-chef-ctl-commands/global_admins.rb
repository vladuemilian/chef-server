#
# Copyright 2015 Chef Software, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'restclient'
require 'json'
require 'sequel'

PLACEHOLDER_GLOBAL_ORG_ID = "00000000000000000000000000000000"

add_command_under_category "grant-global-admin-permissions", "global-admins", "Grant a user the ability to create other users by added the user to the global-admins group.", 2 do

  cmd_args = ARGV[3..-1]
  if cmd_args.length != 1
    msg = "Username is the only argument to grant-global-admin-permissions.\nPlease pass a single argument."
    STDERR.puts msg
    raise SystemExit.new(1, msg)
  end

  username = cmd_args[0]

  db = setup_erchef_db
  global_admins_authz_id = get_global_admins_authz_id(db)
  user_authz_id = get_user_authz_id(db, username)

  # put the user in the global-admins authz group
  headers = {
    :content_type => :json,
    :accept => :json,
    'X-Ops-Requesting-Actor-Id' => running_config['private_chef']['oc_bifrost']['superuser_id']
  }

  base_url = "http://#{running_config['private_chef']['oc_bifrost']['vip']}:#{running_config['private_chef']['oc_bifrost']['port']}"

  RestClient.put("#{base_url}/groups/#{global_admins_authz_id}/actors/#{user_authz_id}", "{}", headers)

  puts "User #{username} was added to global-admins. This user can now list, read, and create users for this Chef Server."
end

add_command_under_category "remove-global-admin-permissions", "global-admins", "Remove all special permission granted to a user from being a global-admin.", 2 do
  cmd_args = ARGV[3..-1]
  if cmd_args.length != 1
    msg = "Username is the only argument to remove-global-admin-permissions.\nPlease pass a single argument."
    STDERR.puts msg
    raise SystemExit.new(1, msg)
  end

  username = cmd_args[0]

  db = setup_erchef_db
  global_admins_authz_id = get_global_admins_authz_id(db)
  user_authz_id = get_user_authz_id(db, username)

  # put the user in the global-admins authz group
  headers = {
    :content_type => :json,
    :accept => :json,
    'X-Ops-Requesting-Actor-Id' => running_config['private_chef']['oc_bifrost']['superuser_id']
  }

  base_url = "http://#{running_config['private_chef']['oc_bifrost']['vip']}:#{running_config['private_chef']['oc_bifrost']['port']}"

  RestClient.delete("#{base_url}/groups/#{global_admins_authz_id}/actors/#{user_authz_id}", headers)

  puts "User #{username} was removed from global-admins. This user can no longer list, read, and create users for this Chef Server."

end

add_command_under_category "list-global-admins", "global-admins", "List users that have global-admins permissions.", 2 do
  cmd_args = ARGV[3..-1]
  if cmd_args.length != 0
    msg = "This command does not accept arguments."
    STDERR.puts msg
    raise SystemExit.new(1, msg)
  end

  db = setup_erchef_db
  global_admins_authz_id = get_global_admins_authz_id(db)
  
  # get all the user authz_ids for all memebers of the global-admins authz group
  headers = {
    :content_type => :json,
    :accept => :json,
    'X-Ops-Requesting-Actor-Id' => running_config['private_chef']['oc_bifrost']['superuser_id']
  }

  base_url = "http://#{running_config['private_chef']['oc_bifrost']['vip']}:#{running_config['private_chef']['oc_bifrost']['port']}"

  results = JSON.parse(RestClient.get("#{base_url}/groups/#{global_admins_authz_id}", headers))

  # get the user's authz id
  users = db[:users].where(:authz_id => results["actors"]).all
  users.each do |user|
    puts user[:username]
  end
end

def setup_erchef_db
  db_host = running_config['private_chef']['postgresql']['vip']
  db_user = running_config['private_chef']['opscode-erchef']['sql_user']
  db_password = running_config['private_chef']['opscode-erchef']['sql_password']
  Sequel.connect("postgres://#{db_user}:#{db_password}@#{db_host}/opscode_chef")
end

def get_global_admins_authz_id(db)
  global_admins_erchef_group = db["SELECT authz_id FROM groups WHERE name='global-admins' AND org_id='#{PLACEHOLDER_GLOBAL_ORG_ID}'"].all

  if global_admins_erchef_group.length != 1
    msg = "More than one global-admins global group was found. Please contact a sysadmin or support (#{global_admins_erchef_group.length} groups found)."
    STDERR.puts msg
    raise SystemExit.new(1, msg)
  end

  global_admins_erchef_group.first[:authz_id]
end

def get_user_authz_id(db, username)
  user = db["SELECT authz_id FROM users WHERE username='#{username}'"].all

  if user.length != 1
    msg = "User #{username} was not found."
    STDERR.puts msg
    raise SystemExit.new(1, msg)
  end

  user.first[:authz_id]
end
