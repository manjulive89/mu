require 'chef/mixin/shell_out'
include Chef::Mixin::PowershellOut
include Chef::Mixin::ShellOut

module Mutools
  module Helper
    def elversion
      return 6 if node.platform_version.to_i == 2013
      return 6 if node.platform_version.to_i == 2014
      return 6 if node.platform_version.to_i == 2015
      return 6 if node.platform_version.to_i == 2016
      node.platform_version.to_i
    end

    def service_user_set?(service, user)
      cmd = powershell_out("$service = Get-WmiObject Win32_service | Where-Object {$_.Name -eq '#{service}'}; $service.startname -eq '#{user}'")
      return cmd.stdout.match(/True/)
    end

    def user_in_local_admin_group?(user)
      cmd = powershell_out("$group = [ADSI]('WinNT://./Administrators'); $group.IsMember('WinNT://#{new_resource.netbios_name}/#{user}')")
      return cmd.stdout.match(/True/)
    end
  end
end

Chef::Recipe.send(:include, Mutools::Helper)
Chef::Resource.send(:include, Mutools::Helper)
Chef::Provider.send(:include, Mutools::Helper)
