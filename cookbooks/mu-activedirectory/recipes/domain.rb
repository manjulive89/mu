#
# Cookbook Name:: mu-activedirectory
# Recipe:: domain
#
# Copyright 2015, eGlobalTech,
#
# All rights reserved - Do Not Redistribute
#

include_recipe 'chef-vault'
domain_admin = chef_vault_item(node['ad']['admin_auth']['vault'], node['ad']['admin_auth']['item'])
can_create_domain = false

case node['platform']
  when "windows"
    ::Chef::Recipe.send(:include, Chef::Mixin::PowershellOut)

    require 'chef/win32/version'
    version = Chef::ReservedNames::Win32::Version.new

    if version.windows_server_2012? || version.windows_server_2012_r2?
      can_create_domain = true
    else
      Chef::Log.info "Requires Windows Server 2012 or 2012R2, current version is #{version})"
    end
  else
    Chef::Log.info("Unsupported platform #{node['platform']}")
end

if can_create_domain
  mu_activedirectory_domain node['ad']['domain_name'] do
    netbios_name node['ad']['netbios_name']
    domain_admin_user domain_admin[node['ad']['admin_auth']['username_field']]
    domain_admin_password domain_admin[node['ad']['admin_auth']['password_field']]
    restore_mode_password domain_admin[node['ad']['admin_auth']['password_field']]
    site_name node['ad']['site_name']
    computer_name node['ad']['computer_name']
    sites node['ad']['sites']
    existing_dc_ips node['ad']['dc_ips']
  end
end
