# Copyright:: Copyright (c) 2019 eGlobalTech, Inc., all rights reserved
#
# Licensed under the BSD-3 license (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License in the root of the project or at
#
#    http://egt-labs.com/mu/LICENSE.html
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


module MU
  # Plugins under this namespace serve as interfaces to host configuration
  # management tools, like Ansible or Puppet.
  class Groomer
    # Support for Ansible as a host configuration management layer.
    class Ansible

      BINDIR = "/usr/local/python-current/bin"

      # @param node [MU::Cloud::Server]: The server object on which we'll be operating
      def initialize(node)
        @config = node.config
        @server = node
        @inventory = Inventory.new(node.deploy)
        @mu_user = node.deploy.mu_user
        @ansible_path = node.deploy.deploy_dir+"/ansible"

        [@ansible_path, @ansible_path+"/roles", @ansible_path+"/vars", @ansible_path+"/group_vars", @ansible_path+"/vaults"].each { |dir|
          if !Dir.exists?(dir)
            MU.log "Creating #{dir}", MU::DEBUG
            Dir.mkdir(dir, 0755)
          end
        }
        installRoles
      end


      # Indicate whether our server has been bootstrapped with Ansible
      def haveBootstrapped?
        @inventory.haveNode?(@server.mu_name)
      end

      # @param vault [String]: A repository of secrets to create/save into.
      # @param item [String]: The item within the repository to create/save.
      # @param data [Hash]: Data to save
      # @param permissions [String]: An implementation-specific string describing what node or nodes should have access to this secret.
      def self.saveSecret(vault: nil, item: nil, data: nil, permissions: nil)
        if vault.nil? or vault.empty? or item.nil? or item.empty?
          raise MuError, "Must call saveSecret with vault and item names"
        end
        if vault.match(/\//) or item.match(/\//) #XXX this should just check for all valid dirname/filename chars
          raise MuError, "Ansible vault/item names cannot include forward slashes"
        end
        pwfile = secret_dir+"/.vault_pw"
        if !File.exists?(pwfile)
          MU.log "Generating Ansible vault password file at #{pwfile}", MU::DEBUG
          File.open(pwfile, File::CREAT|File::RDWR|File::TRUNC, 0400) { |f|
            f.write Password.random(12..14)
          }
        end

        dir = secret_dir+"/"+vault
        path = dir+"/"+item
        Dir.mkdir(dir, 0700) if !Dir.exists?(dir)

        if File.exists?(path)
          MU.log "Overwriting existing vault #{vault} item #{item}"
        end
        File.open(path, File::CREAT|File::RDWR|File::TRUNC, 0600) { |f|
          f.write data
        }
        cmd = %Q{#{BINDIR}/ansible-vault encrypt #{path} --vault-password-file #{pwfile}}
        MU.log cmd
        system(cmd)
      end

      # see {MU::Groomer::Ansible.saveSecret}
      def saveSecret(vault: @server.mu_name, item: nil, data: nil, permissions: "name:#{@server.mu_name}")
        self.class.saveSecret(vault: vault, item: item, data: data, permissions: permissions)
      end

      # Retrieve sensitive data, which hopefully we're storing and retrieving
      # in a secure fashion.
      # @param vault [String]: A repository of secrets to search
      # @param item [String]: The item within the repository to retrieve
      # @param field [String]: OPTIONAL - A specific field within the item to return.
      # @return [Hash]
      def self.getSecret(vault: nil, item: nil, field: nil)
        if vault.nil? or vault.empty?
          raise MuError, "Must call getSecret with at least a vault name"
        end

        pwfile = secret_dir+"/.vault_pw"
        dir = secret_dir+"/"+vault
        if !Dir.exists?(dir)
          raise MuError, "No such vault #{vault}"
        end
        puts dir
        data = nil
        if item
          itempath = dir+"/"+item
          puts itempath
          if !File.exists?(itempath)
            raise MuError, "No such item #{item} in vault #{vault}"
          end
          cmd = %Q{#{BINDIR}/ansible-vault view #{itempath} --vault-password-file #{pwfile}}
          MU.log cmd
          a = `#{cmd}`
          # If we happen to have stored recognizeable JSON, return it as parsed,
          # which is a behavior we're used to from Chef vault. Otherwise, return
          # a String.
          begin
            data = JSON.parse(a)
            if field and data[field]
              data = data[field]
            end
          rescue JSON::ParserError
            data = a
          end
        else
          data = []
          Dir.foreach(dir) { |entry|
            next if entry == "." or entry == ".."
            next if File.directory?(dir+"/"+entry)
            data << entry
          }
        end

        data
      end

      # see {MU::Groomer::Ansible.getSecret}
      def getSecret(vault: nil, item: nil, field: nil)
        self.class.getSecret(vault: vault, item: item, field: field)
      end

      # Delete a Ansible data bag / Vault
      # @param vault [String]: A repository of secrets to delete
      def self.deleteSecret(vault: nil, item: nil)
        if vault.nil? or vault.empty?
          raise MuError, "Must call deleteSecret with vault name"
        end
        MU.log "MU::Groomer::Ansible.deleteSecret called, now implement it dumbass", MU::ERR
      end

      # see {MU::Groomer::Ansible.deleteSecret}
      def deleteSecret(vault: nil, item: nil)
        self.class.deleteSecret(vault: vault, item: nil)
      end

      # Invoke the Ansible client on the node at the other end of a provided SSH
      # session.
      # @param purpose [String]: A string describing the purpose of this client run.
      # @param max_retries [Integer]: The maximum number of attempts at a successful run to make before giving up.
      # @param output [Boolean]: Display Ansible's regular (non-error) output to the console
      # @param override_runlist [String]: Use the specified run list instead of the node's configured list
      def run(purpose: "Ansible run", update_runlist: true, max_retries: 5, output: true, override_runlist: nil, reboot_first_fail: false, timeout: 1800)
        pwfile = secret_dir+"/.vault_pw"

        cmd = %Q{cd #{@ansible_path} && #{BINDIR}/ansible-playbook -i hosts #{@server.config['name']}.yml --limit=#{@server.mu_name} --vault-password-file #{pwfile}}

        MU.log cmd
        system(cmd)
      end

      # This is a stub; since Ansible is effectively agentless, this operation
      # doesn't have meaning.
      def preClean(leave_ours = false)
      end

      # This is a stub; since Ansible is effectively agentless, this operation
      # doesn't have meaning.
      def reinstall
      end

      # Bootstrap our server with Ansible- basically, just make sure this node
      # is listed in our deployment's Ansible inventory.
      def bootstrap
        @inventory.add(@server.config['name'], @server.mu_name)
        play = {
          "hosts" => @server.config['name']
        }

        if @server.config['ssh_user'] != "root"
          play["become"] = "yes"
        end

        if @server.config['run_list'] and !@server.config['run_list'].empty?
          play["roles"] = @server.config['run_list']
        end

        File.open(@ansible_path+"/"+@server.config['name']+".yml", File::CREAT|File::RDWR|File::TRUNC, 0600) { |f|
          f.flock(File::LOCK_EX)
          f.puts [play].to_yaml
          f.flock(File::LOCK_UN)
        }
      end

      # Synchronize the deployment structure managed by {MU::MommaCat} into some Ansible variables, so that nodes can access this metadata.
      # @return [Hash]: The data synchronized.
      def saveDeployData
        @server.describe(update_cache: true) # Make sure we're fresh

        allvars = {
          "deployment" => @server.deploy.deployment,
          "service_name" => @config["name"],
          "windows_admin_username" => @config['windows_admin_username'],
          "mu_environment" => MU.environment.downcase,
        }
        allvars['deployment']['ssh_public_key'] = @server.deploy.ssh_public_key

        if @server.config['cloud'] == "AWS"
          allvars["ec2"] = MU.structToHash(@server.cloud_desc, stringify_keys: true)
        end

        if @server.windows?
          allvars['windows_admin_username'] = @config['windows_admin_username']
        end

        if !@server.cloud.nil?
          allvars["cloudprovider"] = @server.cloud
        end

        File.open(@ansible_path+"/vars/main.yml", File::CREAT|File::RDWR|File::TRUNC, 0600) { |f|
          f.flock(File::LOCK_EX)
          f.puts allvars.to_yaml
          f.flock(File::LOCK_UN)
        }

        groupvars = {}
        if @server.deploy.original_config.has_key?('parameters')
          groupvars["mu_parameters"] = @server.deploy.original_config['parameters']
        end
        if !@config['application_attributes'].nil?
          groupvars["application_attributes"] = @config['application_attributes']
        end

        File.open(@ansible_path+"/group_vars/"+@server.config['name']+".yml", File::CREAT|File::RDWR|File::TRUNC, 0600) { |f|
          f.flock(File::LOCK_EX)
          f.puts groupvars.to_yaml
          f.flock(File::LOCK_UN)
        }

        allvars['deployment']
      end

      # Expunge Ansible resources associated with a node.
      # @param node [String]: The Mu name of the node in question.
      # @param vaults_to_clean [Array<Hash>]: Some vaults to expunge
      # @param noop [Boolean]: Skip actual deletion, just state what we'd do
      # @param nodeonly [Boolean]: Just delete the node and its keys, but leave other artifacts
      def self.cleanup(node, vaults_to_clean = [], noop = false, nodeonly: false)
        deploy = MU::MommaCat.new(MU.deploy_id)
        inventory = Inventory.new(deploy)
        ansible_path = deploy.deploy_dir+"/ansible"
        inventory.remove(node)
      end

      def self.listSecrets(user = MU.mu_user)
        path = secret_dir(user)
        found = []
        Dir.foreach(path) { |entry|
          next if entry == "." or entry == ".."
          next if !File.directory?(path+"/"+entry)
          found << entry
        }
        found
      end

      private

      # Figure out where our main stash of secrets is, and make sure it exists
      def secret_dir
        MU::Groomer::Ansible.secret_dir(@mu_user)
      end

      # Figure out where our main stash of secrets is, and make sure it exists
      def self.secret_dir(user = MU.mu_user)
        path = MU.dataDir(user) + "/ansible-secrets"
        Dir.mkdir(path, 0755) if !Dir.exists?(path)

        path
      end

      def isAnsibleRole?(path)
        true # XXX no
      end

      # Find all of the Ansible roles in the various configured Mu repositories
      # and 
      def installRoles
        roledir = @ansible_path+"/roles"

        canon_links = {}

        # Hook up any Ansible roles listed in our platform repos
        $MU_CFG['repos'].each { |repo|
          repo.match(/\/([^\/]+?)(\.git)?$/)
          shortname = Regexp.last_match(1)
          repodir = MU.dataDir + "/" + shortname
          ["roles", "ansible/roles"].each { |subdir|
            next if !Dir.exists?(repodir+"/"+subdir)
            Dir.foreach(repodir+"/"+subdir) { |role|
              next if [".", ".."].include?(role)
              realpath = repodir+"/"+subdir+"/"+role
              link = roledir+"/"+role
              
              if isAnsibleRole?(realpath)
                if !File.exists?(link)
                  File.symlink(realpath, link)
                  canon_links[role] = realpath
                elsif File.symlink?(link)
                  cur_target = File.readlink(link)
                  if cur_target == realpath
                    canon_links[role] = realpath
                  elsif !canon_links[role]
                    File.unlink(link)
                    File.symlink(realpath, link)
                    canon_links[role] = realpath
                  end
                end
              end
            }
          }
        }

        # Now layer on everything bundled in the main Mu repo
        Dir.foreach(MU.myRoot+"/ansible/roles") { |role|
          next if [".", ".."].include?(role)
          next if File.exists?(roledir+"/"+role)
          File.symlink(MU.myRoot+"/ansible/roles/"+role, roledir+"/"+role)
        }

        if @server.config['run_list']
          @server.config['run_list'].each { |role|
            if !File.exists?(roledir+"/"+role)
              if role.match(/[^\.]\.[^\.]/)
# TODO be able to toggle this behavior off
                system(%Q{#{BINDIR}/ansible-galaxy --roles-path #{roledir} install #{role}})
              else
                canon_links.keys.each { |longrole|
                  if longrole.match(/\.#{Regexp.quote(role)}$/)
                    File.symlink(roledir+"/"+longrole, roledir+"/"+role)
                    break
                  end
                }
              end
            end
          }
        end
      end

      # Simple interface for an Ansible inventory file.
      class Inventory

        # @param deploy [MU::MommaCat]
        def initialize(deploy)
          @deploy = deploy
          @ansible_path = @deploy.deploy_dir+"/ansible"
          if !Dir.exists?(@ansible_path)
            Dir.mkdir(@ansible_path, 0755)
          end

          @lockfile = File.open(@ansible_path+"/.hosts.lock", File::CREAT|File::RDWR, 0600)
        end

        # See if we have a particular node in our inventory.
        def haveNode?(name)
          lock
          read
          @inv.each_pair { |group, nodes|
            if nodes.include?(name)
              unlock
              return true
            end
          }
          unlock
          false
        end

        # Add a node to our Ansible inventory
        # @param group [String]: The host group to which the node belongs
        # @param name [String]: The hostname or IP of the node
        def add(group, name)
          if group.nil? or group.empty? or name.nil? or name.empty?
            raise MuError, "Ansible::Inventory.add requires both a host group string and a name"
          end
          lock
          read
          @inv[group] ||= []
          @inv[group] << name
          @inv[group].uniq!
          save!
          unlock
        end

        # Remove a node from our Ansible inventory
        # @param name [String]: The hostname or IP of the node
        def remove(name)
          lock
          read
          @inv.each_pair { |group, nodes|
            nodes.delete(name)
          }
          save!
          unlock
        end

        private

        def lock
          @lockfile.flock(File::LOCK_EX)
        end

        def unlock
          @lockfile.flock(File::LOCK_UN)
        end

        def save!
          @inv ||= {}

          File.open(@ansible_path+"/hosts", File::CREAT|File::RDWR|File::TRUNC, 0600) { |f|
            @inv.each_pair { |group, hosts|
              next if hosts.size == 0 # don't write empty groups
              f.puts "["+group+"]"
              f.puts hosts.join("\n")
            }
          }
        end

        def read
          @inv = {}
          if File.exists?(@ansible_path+"/hosts")
            section = nil
# XXX need that flock
            File.readlines(@ansible_path+"/hosts").each { |l|
              l.chomp!
              l.sub!(/#.*/, "")
              next if l.empty?
              if l.match(/\[(.+?)\]/)
                section = Regexp.last_match[1]
                @inv[section] ||= []
              else
                @inv[section] << l
              end
            }
          end

          @inv
        end

      end

    end # class Ansible
  end # class Groomer
end # Module Mu
