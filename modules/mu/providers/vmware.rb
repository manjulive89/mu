# Copyright:: Copyright (c) 2017 eGlobalTech, Inc., all rights reserved
#
# Licensed under the BSD-3 license (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License in the root of the project or at
#
#     http://egt-labs.com/mu/LICENSE.html
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require "net/http"
require 'net/https'
require 'vsphere-automation-sdk'
require 'vsphere-automation-content'
require 'vsphere-automation-vcenter'
require 'vsphere-automation-cis'

module MU
  class Cloud
    # Support for VMWare as a provisioning layer.
    class VMWare
      @@authtoken = nil
      @@default_project = nil
      @@myRegion_var = nil
      @@my_hosted_cfg = nil
      @@authorizers = {}
      @@acct_to_profile_map = {}
      @@enable_semaphores = {}
      @@readonly_semaphore = Mutex.new
      @@readonly = {}


      # Module used by {MU::Cloud} to insert additional instance methods into
      # instantiated resources in this cloud layer.
      module AdditionalResourceMethods
        # @return [String]
#        def url
#          desc = cloud_desc
#          (desc and desc.self_link) ? desc.self_link : nil
#        end
      end

      # Any cloud-specific instance methods we require our resource
      # implementations to have, above and beyond the ones specified by
      # {MU::Cloud}
      # @return [Array<Symbol>]
      def self.required_instance_methods
        []
      end

      # Is this a "real" cloud provider, or a stub like CloudFormation?
      def self.virtual?
        false
      end

      class VSphereError < MU::MuError
      end

      class NSX

        class NSXError < MU::MuError
        end
        attr_reader :base_url
        attr_reader :mgr_url
        attr_reader :reverse_proxy_url

        def initialize(credentials = nil, habitat: nil)
          @credentials = credentials
          @sddc = habitat
          @sddc ||= MU::Cloud::VMWare.defaultSDDC(credentials)
          org_desc = MU::Cloud::VMWare::VMC.getOrg(credentials)
          @org = org_desc['id']
          sddc_desc = MU::Cloud::VMWare::VMC.callAPI("orgs/"+@org+"/sddcs/#{@sddc}", credentials: credentials)
          @base_url = sddc_desc["resource_config"]["nsx_api_public_endpoint_url"]
          @mgr_url = sddc_desc["resource_config"]["nsx_mgr_url"]
          @reverse_proxy_url = sddc_desc["resource_config"]["nsx_reverse_proxy_url"]
          @username = sddc_desc["resource_config"]["cloud_username"]
          @password = sddc_desc["resource_config"]["cloud_password"]
          resp = callAPI("policy/api/v1/infra/domains")["results"]
          @domains = resp.map { |d| d["id"] }
          @default_domain = @domains.include?("cgw") ? "cgw" : @domains.first
#pp callAPI("policy/api/v1/infra/tier-1s/cgw/segments")
#pp callAPI("policy/api/v1/infra/sites")
#callAPI("orgs/#{@org}/sddcs/#{@sddc}/networks/4.0/sddc/networks")
        end

        def listNetworks
          resp = callAPI("policy/api/v1/infra/segments")
          if resp and resp['results']
            return resp['results']
          end
          nil
        end

# https://vdc-download.vmware.com/vmwb-repository/dcr-public/9e1c6bcc-85db-46b6-bc38-d6d2431e7c17/30af91b5-3a91-4d5d-8ed5-a7d806764a16/api_includes/policy_networking_connectivity_segment_segments.html
        def createUpdateSegment(params)
          resp = callAPI("policy/api/v1/infra/segments/#{params['id']}", method: "PATCH", params: params)
pp resp
# XXX some validation is obviously warranted
#PATCH https://<policy-mgr>/policy/api/v1/infra/segments/web-tier
#  {
#    "display_name":"web-tier",
#    "subnets": [
#      {
#        "gateway_address": "40.1.1.1/16",
#        "dhcp_ranges": [ "40.1.2.0/24" ]
#      }
#    ],
#    "connectivity_path": "/infra/tier-1s/mgw"
#  }
        end

        def listPublicIPs
          callAPI("cloud-service/api/v1/public-ips")["results"]
        end

        def releasePublicIP(id)
          callAPI("cloud-service/api/v1/public-ips/#{id}", method: "DELETE")
        end

        def allocatePublicIP(name)

          listPublicIPs.each { |ip|
            return ip if ip["display_name"] == name
          }

          callAPI("cloud-service/api/v1/public-ips/#{name}", method: "PUT", params: { display_name: name })
        end

        def listNATRules(section: "USER", tier: 1)
          if tier == 0
            callAPI("policy/api/v1/infra/tier-0s/vmc/nat/#{section}/nat-rules")["results"]
          else
            callAPI("policy/api/v1/infra/tier-1s/cgw/nat/#{section}/nat-rules")["results"]
          end
        end

        def deleteNATRule(id, section: "USER", tier: 1)
          if tier == 0
            callAPI("policy/api/v1/infra/tier-0s/vmc/nat/#{section}/nat-rules/#{id}", method: "DELETE")
          else
            callAPI("policy/api/v1/infra/tier-1s/cgw/nat/#{section}/nat-rules/#{id}", method: "DELETE")
          end
        end

        def createUpdateNATRule(name, outside, inside = nil, port_range: "0-65535", section: "USER", description: nil, inbound: false, sequence: 10)
          params = {
            display_name: name,
            description: description,
            service: "",
            sequence_number: sequence,
            enabled: true,
            logging: true,
#            resource_type: "PolicyNatRule",
#            scope: ["infra/tier-0s/provider1/local-services/localService1/interfaces/internet"],
#            scope: ["infra/tier-0s/vmc/local-services/localService1/interfaces/internet"],
          }
          if inbound
            params[:action] = "DNAT"
            params[:translated_network] = inside
            params[:translated_ports] = port_range.to_s
            params[:destination_network] = outside
            params[:firewall_match] = "MATCH_INTERNAL_ADDRESS"
          else
            params[:action] = "REFLEXIVE"
            params[:translated_network] = outside
            params[:source_network] = inside
            params[:firewall_match] = "MATCH_EXTERNAL_ADDRESS"
          end
          callAPI("policy/api/v1/infra/tier-1s/cgw/nat/#{section}/nat-rules/#{name}", method: "PATCH", params: params)
        end

        def listServices
          callAPI("policy/api/v1/ns-service-groups")
        end

        def createIPSet(name, cidrs)
          params = {
            display_name: name,
            ip_addresses: cidrs
          }
          callAPI("api/v1/ip-sets", method: "POST", params: params)
        end

        # We can't actually do this, because the API gives us a 403. Because
        # reasons.
        def listIPSets
          callAPI("api/v1/ip-sets")["results"]
#          listGroups.each { |g|
#            next if !g['members']
#            g['members'].each { |m|
#              if m["target_type"] == "IPSet" and m["target_property"] == "id"
#                pp callAPI("api/v1/ip-sets/#{m["value"]}")
#              end
#            }
#          }
        end

        def listGroups
          callAPI("api/v1/ns-groups")["results"]
        end

        def listPolicies(domain = nil)
          domain ||= @default_domain
          callAPI("policy/api/v1/infra/domains/#{domain}/gateway-policies")["results"]
        end

        def listRules(policy_id, domain = nil)
          domain ||= @default_domain
          callAPI("policy/api/v1/infra/domains/#{domain}/gateway-policies/#{policy_id}/rules")["results"]
        end

        def createUpdateIPPool(name, description: nil, tags: nil)
          params = {
            "display_name" => name,
          }
          params["description"] = description if description
          if tags
            params["tags"] = tags.keys.map { |k| { "scope" => k, "tag" => @tags[k] } }
          end
          callAPI("policy/api/v1/infra/ip-pools/#{name}", method: "PATCH", params: params)
        end

        def deleteSegment(id)
          callAPI("policy/api/v1/infra/segments/#{id}", method: "DELETE")
        end

        # Make an API request to NSX
        # @param path [String]
        # @param credentials [String]
        # @return [Array,Hash]
        def callAPI(path, method: "GET", params: nil, full_url: nil, redirects: 0, base_url: @base_url)
          uri = full_url ? URI(full_url) : URI(base_url.gsub(/\/$/, '')+"/"+path)

          req = if method == "POST"
            Net::HTTP::Post.new(uri)
          elsif method == "PUT"
            Net::HTTP::Put.new(uri)
          elsif method == "DELETE"
            Net::HTTP::Delete.new(uri)
          elsif method == "PATCH"
            Net::HTTP::Patch.new(uri)
          else
            if params and !params.empty?
              uri.query = URI.encode_www_form(params)
            end
            Net::HTTP::Get.new(uri)
          end

          if ["POST", "PATCH", "PUT"].include?(method) and params and !params.empty?
            req.body = JSON.generate(params)
          end

          req['Content-type'] = "application/json"
#          if path.match(/\/login$/)
#            req.basic_auth @username, @password
#          else
            req['csp-auth-token'] = MU::Cloud::VMWare::VMC.getToken(@credentials)
#          end

          MU.log "NSX #{method} #{uri.to_s}", MU::NOTICE, details: params
          resp = Net::HTTP.start(uri.host, uri.port, :use_ssl => true) do |http|
            http.request(req)
          end

          if ["301", "302"].include?(resp.code)
#            if full_url == resp['location'] or redirects > 5
            if redirects > 5
              raise NSXError.new "I seem to be in redirect loop. Latest redirect:", details: { full_url => resp['location'] }
            end
            MU.log "Redirecting to #{resp['location']}", MU::NOTICE, details: resp.body
            return callAPI(path, method: method, params: params, full_url: resp['location'], redirects: redirects+1)
          end

          unless resp.code == "200"
            raise NSXError.new "Bad response from NSX API (#{resp.code.to_s})", details: resp.body
          end

          if resp.body and !resp.body.empty?
            JSON.parse(resp.body)
          else
            nil
          end
        end
      end

      class VMC
        AUTH_URI = URI "https://console.cloud.vmware.com/csp/gateway/am/api/auth/api-tokens/authorize"
        API_URL = "https://vmc.vmware.com/vmc/api"

        class VMCError < MU::MuError
        end

        def initialize(credentials = nil, habitat: nil)
          @credentials = credentials
          @sddc = habitat
          @sddc ||= MU::Cloud::VMWare.defaultSDDC(credentials)
          org_desc = MU::Cloud::VMWare::VMC.getOrg(credentials)
          @org = org_desc['id']
#pp callAPI("policy/api/v1/infra/tier-1s/cgw/segments")
#pp callAPI("policy/api/v1/infra/sites")
#callAPI("orgs/#{@org}/sddcs/#{@sddc}/networks/4.0/sddc/networks")
        end

        @@vmc_tokens = {}

        # Fetch a live authorization token from the VMC API, if there's a +token+ underneath the +vmc+ subsection configured credentials
        # @param credentials [String]
        # @return [String]
        def self.getToken(credentials = nil)
          @@vmc_tokens ||= {}
          if @@vmc_tokens[credentials]
            return @@vmc_tokens[credentials]['access_token']
          end
          cfg = MU::Cloud::VMWare.credConfig(credentials)
          if !cfg or !cfg['vmc'] or !cfg['vmc']['token']
            raise MuError, "No VMWare credentials #{credentials ? credentials : "<default>"} found or no VMC token configured"
          end

          resp = nil

          req = Net::HTTP::Post.new(AUTH_URI)
          req['Content-type'] = "application/json"
          req.set_form_data('refresh_token' => cfg['vmc']['token'])

          resp = Net::HTTP.start(AUTH_URI.hostname, AUTH_URI.port, :use_ssl => true) {|http|
            http.request(req)
          }

          unless resp.code == "200"
            raise MuError.new "Failed to authenticate to VMC with auth token under credentials #{credentials ? credentials : "<default>"}", details: resp.body
          end
          @@vmc_tokens[credentials] = JSON.parse(resp.body)
          @@vmc_tokens[credentials]['last_fetched'] = Time.now
          @@vmc_tokens[credentials]['access_token']
        end

        @@org_cache = {}

        # If the given set of credentials has VMC configured, return the default
        # organization.
        # @param credentials [String]
        # @return [Hash]
        def self.getOrg(credentials = nil, use_cache: true)
          if @@org_cache[credentials] and use_cache
            return @@org_cache[credentials]
          end
          cfg = MU::Cloud::VMWare.credConfig(credentials)
          return if !cfg or !cfg['vmc']

          orgs = callAPI("orgs", credentials: credentials)
          if orgs.size == 1
            @@org_cache[credentials] = orgs.first
          elsif cfg and cfg['vmc'] and cfg['vmc']['org']
            orgs.each { |o|
              if [org['user_id'], org['user_name'], org['name'], org['display_name']].include?(cfg['vmc']['org'])
                @@org_cache[credentials] = o
                break
              end
            }
          elsif orgs.size > 1
            raise MuError.new, "I see multiple VMC orgs with credentials #{credentials ? credentials : "<default>"}, set vmc_org to specify one as default", details: orgs.map { |o| o['display_name'] }
          end

          @@org_cache[credentials]
        end

        def getOrg(use_cache: true)
          MU::Cloud::VMWare::VPC.getOrg(@credentials, use_cache: use_cache)
        end

        def self.setAWSIntegrations(credentials = nil)
          cfg = MU::Cloud::VMWare.credConfig(credentials)
          credname = credentials
          credname ||= "<default>"
          return if !cfg or !cfg['vmc'] or !cfg['vmc']['connections']
          org = getOrg(credentials)['id']

          aws = MU::Cloud.cloudClass("AWS")
          cfg['vmc']['connections'].each_pair { |awscreds, vpcs|
            credcfg= aws.credConfig(awscreds)
            if !credcfg
              MU.log "I have a VMWare VMC integration under #{credname} configured for an AWS account named '#{awscreds}', but no such AWS credential set exists", MU::ERR
              next
            end
            acctnum = aws.credToAcct(awscreds)

            resp = begin
              callAPI("orgs/"+org+"/account-link/connected-accounts")
            rescue VMCError => e
              MU.log e.message, MU::WARN
            end
            aws_account = resp.select { |a| a["account_number"] == acctnum }.first if resp

            if !aws_account
              stackname = "vmware-vmc-#{credname.gsub(/[^a-z0-9\-]/i, '')}-to-aws-#{awscreds}"
              stack_cfg = callAPI("orgs/"+org+"/account-link")
              MU.log "Creating account link between VMWare VMC and AWS account #{awscreds}", details: stack_cfg
              begin
                aws.cloudformation(credentials: awscreds, region: region).create_stack(
                  stack_name: stackname,
                  capabilities: ["CAPABILITY_IAM"],
                  template_url: stack_cfg["template_url"]
                )
              rescue Aws::CloudFormation::Errors::AlreadyExistsException
                MU.log "Account link CloudFormation stack already exists", MU::NOTICE, details: stackname
              end

              desc = nil
              loop_if = Proc.new {
                desc = aws.cloudformation(credentials: awscreds, region: region).describe_stacks(
                  stack_name: stackname,
                ).stacks.first

                (!desc or desc.stack_status == "CREATE_IN_PROGRESS")
              }
              MU.retrier(loop_if: loop_if, wait: 60) {
                MU.log "Waiting for CloudFormation stack #{stackname} to complete" , MU::NOTICE, details: (desc.stack_status if desc)
              }
              if desc.stack_status != "CREATE_COMPLETE"
                MU.log "Failed to create VMC <=> AWS connective CloudFormation stack", MU::ERR, details: desc

              end
            end

            # XXX this is a dumb assumption
            my_sddc = callAPI("orgs/"+org+"/sddcs").first
            sddc_id = my_sddc["id"]

            connected = {}
            callAPI("orgs/"+org+"/account-link/sddc-connections", params: { "sddc" => sddc_id} ).each { |cnxn|

              connected[cnxn['vpc_id']] ||= []
              connected[cnxn['vpc_id']] << cnxn['subnet_id']
            }

            vpcs.each { |vpc_cfg|
              region = vpc_cfg['region'] || aws.myRegion(awscreds)

              if !vpc_cfg['auto']
# XXX create if does not exist
              end

              vpcs_confd = callAPI("orgs/"+org+"/account-link/compatible-subnets", params: { "linkedAccountId" => aws_account["id"], "region" => region, "forceRefresh" => true })["vpc_map"]
              vpcs_confd.each_pair { |vpc_id, vpc_desc|
                if [vpc_id, vpc_desc['description'], vpc_desc['cidr_block']].include?(vpc_cfg['vpc'])
# XXX honor subnet_prefs, etc, like just like an ordinary resource
                  vpc_desc["subnets"].reject { |s| !s["compatible"] }.each { |subnet|
                    next if connected[vpc_id] and connected[vpc_id].include?(subnet['subnet_id'])
                    subnet.reject! { |k, v|
                      v.nil? or !%w{connected_account_id region_name availability_zone subnet_id subnet_cidr_block is_compatible vpc_id vpc_cidr_block name}.include?(k)
                    }
                    callAPI(
                      "orgs/"+org+"/account-link/compatible-subnets",
                      method: "POST",
                      params: subnet
                    )
                    connected[vpc_id] ||= []
                    connected[vpc_id] << subnet['subnet_id']
                  }
                end
              }
            }

pp my_sddc
exit
            connected.each_pair { |vpc_id, subnet_ids|
MU.log "attempting to glue #{vpc_id}", MU::NOTICE, details: subnet_ids
              entangle = {
                "sddc_id" => sddc_id,
                "name" => my_sddc["name"],
                "account_link_sddc_config" => [{
                  "connected_account_id" => aws_account["id"],
                  "customer_subnet_ids" => subnet_ids
                }],
#                "account_link_config" => { "delay_account_link" => false }
              }
              pp callAPI("orgs/"+org+"/sddcs", method: "POST", params: entangle)
            }

#            callAPI("orgs/"+org+"/sddcs").each { |sddc|
#              sddc["resource_config"]["sddc_id"]
#MU.log "sddc", MU::NOTICE, details: sddc
#            }

          }
        end

        # Make an API request to VMC
        # @param path [String]
        # @param credentials [String]
        # @return [Array,Hash]
        def self.callAPI(path, method: "GET", credentials: nil, params: nil, base_url: API_URL, full_url: nil, redirects: 0, debug: false)
          uri = full_url ? URI(full_url) : URI(base_url.sub(/\/$/, '')+"/"+path)

          req = if method == "POST"
            Net::HTTP::Post.new(uri)
          elsif method == "DELETE"
            Net::HTTP::Delete.new(uri)
          elsif method == "PATCH"
            Net::HTTP::Patch.new(uri)
          elsif method == "PUT"
            Net::HTTP::Put.new(uri)
          else
            if params and !params.empty?
              uri.query = URI.encode_www_form(params)
            end
            Net::HTTP::Get.new(uri)
          end

          if method != "GET" and params and !params.empty?
            req.body = JSON.generate(params)
          end

          req['Content-type'] = "application/json"
          req['csp-auth-token'] = getToken(credentials)

          MU.log "VMC #{method} #{uri.to_s}", MU::NOTICE, details: req.body
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.set_debug_output($stdout) if debug
          http.start
          resp = http.request(req)
          http.finish

          if ["301", "302"].include?(resp.code)
            if full_url == resp['location'] or redirects > 5
              raise VMCError.new "I seem to be in redirect loop. Latest redirect:", details: { full_url => resp['location'] }
            end
            MU.log "Redirecting to #{resp['location']}", MU::NOTICE, details: resp.inspect
            return callAPI(path, method: method, credentials: credentials, params: params, full_url: resp['location'], redirects: redirects+1)
          elsif ["202"].include?(resp.code)
            org = getOrg(credentials)['id']
            task = JSON.parse(resp.body)
            MU.retrier(loop_if: Proc.new { task["status"] == "STARTED" }, wait: 15, max: 20) {
              MU.log "blocking on task in progress orgs/#{org}/tasks/#{task['id']}", MU::WARN, details: task
              task = callAPI("orgs/#{org}/tasks/#{task['id']}", method: "GET", credentials: credentials)
              if task["status"] == "FAILED"
                raise VMCError.new "#{method} #{uri.to_s} task failed", details: task
              end
            }
            return task
          end

          unless resp.code == "200"
            raise VMCError.new "Bad response from VMC API (#{resp.code.to_s})", details: resp.body
          end

          JSON.parse(resp.body)
        end
      end

      # A hook that is always called just before any of the instance method of
      # our resource implementations gets invoked, so that we can ensure that
      # repetitive setup tasks (like resolving +:resource_group+ for Azure
      # resources) have always been done.
      # @param cloudobj [MU::Cloud]
      # @param deploy [MU::MommaCat]
      def self.resourceInitHook(cloudobj, deploy)
        class << self
          attr_reader :sddc
        end
        return if !cloudobj

        if deploy        
          if cloudobj.config['habitat']
            habref = MU::Config::Ref.get(cloudobj.config['habitat'])
            cloudobj.instance_variable_set(:@sddc, habref.id)
          else
            cloudobj.instance_variable_set(:@sddc, MU::Cloud::VMWare.defaultSDDC(cloudobj.credentials))
          end
        end
      end

      # If we're running this cloud, return the MU.muCfg blob we'd use to
      # describe this environment as our target one.
      def self.hosted_config
        nil
      end

      # A non-working example configuration
      def self.config_example
        sample = hosted_config
        sample ||= {
          "vmc_token" => "foobarbaz"
        }
        sample
      end

      # Return the name strings of all known sets of credentials for this cloud
      # @return [Array<String>]
      def self.listCredentials
        if !MU.muCfg['vmware']
          return hosted? ? ["#default"] : nil
        end

        MU.muCfg['vmware'].keys
      end

      @@habmap = {}

      # @param cloudobj [MU::Cloud::VMWare]: The resource from which to extract the habitat id
      # @return [String,nil]
      def self.habitat(cloudobj, nolookup: false, deploy: nil)
        @@habmap ||= {}

        nil
      end

      @@default_sddc_cache = {}

      # Our credentials can map to one or more Software-Defined Data Centers.
      # It's usually exactly one, so many methods should be able to just assume
      # we know what they mean when they don't specify.
      # @param credentials [String]
      # @return [String]
      def self.defaultSDDC(credentials = nil)
        if @@default_sddc_cache.has_key?(credentials)
          return @@default_sddc_cache[credentials]
        end
        cfg = credConfig(credentials)
        if !cfg or !cfg['sddc']
#          if hosted?
#            @@default_sddc_cache[credentials] = myProject
#            return myProject 
#          end
          if cfg
            sddcs = listHabitats(credentials)
            if sddcs.size == 1
              @@default_sddc_cache[credentials] = sddcs[0]
              return sddcs[0]
            end
          end
        end
        return nil if !cfg or !cfg['sddc']

        @@default_sddc_cache[credentials] = cfg['sddc']
        cfg['sddc']
      end

      # Resolve the administrative Cloud Storage bucket for a given credential
      # set, or return a default.
      # @param credentials [String]
      # @return [String]
      def self.adminBucketName(credentials = nil)
         #XXX find a default if this particular account doesn't have a log_bucket_name configured
        cfg = credConfig(credentials)
        if cfg.nil?
          raise MuError, "Failed to load VMWare credential set #{credentials}"
        end
        cfg['log_bucket_name']
      end

      # Resolve the administrative Cloud Storage bucket for a given credential
      # set, or return a default.
      # @param credentials [String]
      # @return [String]
      def self.adminBucketUrl(credentials = nil)
        nil
      end

      # Return the MU.muCfg data associated with a particular profile/name/set
      # of credentials. If no account name is specified, will return one
      # flagged as default. Returns nil if VMWare is not configured. Throws an
      # exception if an account name is specified which does not exist.
      # @param name [String]: The name of the key under 'vmware' in mu.yaml to return
      # @return [Hash,nil]
      def self.credConfig(name = nil, name_only: false)
        # If there's nothing in mu.yaml (which is wrong), but we're running
        # on a machine hosted in VMWare, fake it with that machine's service
        # account and hope for the best.
        if !MU.muCfg['vmware'] or !MU.muCfg['vmware'].is_a?(Hash) or MU.muCfg['vmware'].size == 0
          return @@my_hosted_cfg if @@my_hosted_cfg

          if hosted?
            @@my_hosted_cfg = hosted_config
            return name_only ? "#default" : @@my_hosted_cfg
          end

          return nil
        end

        if name.nil?
          MU.muCfg['vmware'].each_pair { |set, cfg|
            if cfg['default'] or MU.muCfg['vmware'].size == 1
              return name_only ? set : cfg
            end
          }
        else
          if MU.muCfg['vmware'][name]
            return name_only ? name : MU.muCfg['vmware'][name]
          elsif @@acct_to_profile_map[name.to_s]
            return name_only ? name : @@acct_to_profile_map[name.to_s]
          end
# XXX whatever process might lead us to populate @@acct_to_profile_map with some mappings, like projectname -> account profile, goes here
          return nil
        end
      end

      # If we've configured VMC as a provider, or are simply hosted in VMWare, 
      # decide what our default region is.
      # XXX is this even applicable? should we just inherit the AWS region of
      # the VMC cluster? does it mean anything to us?
      def self.myRegion(credentials = nil)
        cfg = credConfig(credentials)
        if cfg and cfg['region']
          @@myRegion_var = cfg['region']
#        elsif MU::Cloud::VMWare.hosted?
        else
          @@myRegion_var = ""
        end
        @@myRegion_var
      end

      # Do cloud-specific deploy instantiation tasks, such as copying SSH keys
      # around, sticking secrets in buckets, creating resource groups, etc
      # @param deploy [MU::MommaCat]
      def self.initDeploy(deploy)
      end

      # Purge cloud-specific deploy meta-artifacts (SSH keys, resource groups,
      # etc)
      # @param deploy_id [MU::MommaCat]
      def self.cleanDeploy(deploy_id, credentials: nil, noop: false)
        removeDeploySecretsAndRoles(deploy_id, noop: noop, credentials: credentials)
      end

      # Plant a Mu deploy secret into a storage bucket somewhere for so our kittens can consume it
      # @param deploy_id [String]: The deploy for which we're writing the secret
      # @param value [String]: The contents of the secret
      def self.writeDeploySecret(deploy_id, value, name = nil, credentials: nil)
        name ||= deploy_id+"-secret"
      end

      # Remove the service account and various deploy secrets associated with a deployment. Intended for invocation from MU::Cleanup.
      # @param deploy_id [String]: The deploy for which we're granting the secret
      # @param noop [Boolean]: If true, will only print what would be done
      def self.removeDeploySecretsAndRoles(deploy_id = MU.deploy_id, flags: {}, noop: false, credentials: nil)
        cfg = credConfig(credentials)
      end

      # Grant access to appropriate Cloud Storage objects in our log/secret bucket for a deploy member.
      # @param acct [String]: The service account (by email addr) to which we'll grant access
      # @param deploy_id [String]: The deploy for which we're granting the secret
      # XXX add equivalent for AWS and call agnostically
      def self.grantDeploySecretAccess(acct, deploy_id = MU.deploy_id, name = nil, credentials: nil)
        name ||= deploy_id+"-secret"
      end

      @@is_in_gcp = nil

      # Alias for #{MU::Cloud::VMWare.hosted?}
      def self.hosted
        MU::Cloud::VMWare.hosted?
      end

      # Determine whether we (the Mu master, presumably) are hosted in this
      # cloud.
      # @return [Boolean]
      def self.hosted?
        false
      end

      def self.loadCredentials(scopes = nil, credentials: nil)
        nil
      end

      # Fetch a URL
      def self.get(url)
        uri = URI url
        resp = nil

        Net::HTTP.start(uri.host, uri.port) do |http|
          resp = http.get(uri)
        end

        unless resp.code == "200"
          puts resp.code, resp.body
          exit
        end
        resp.body
      end

      def self.folderToID(name, credentials = nil)
        folders = folder(credentials: credentials).list().value
        folders.each { |f|
          if [f.folder, f.name].include?(name)
            return f.folder
          end
        }
        nil
      end

      @@all_sddcs = {}

      # List all SDDCs available to our credentials
      def self.listHabitats(credentials = nil, use_cache: true)
        if use_cache and @@all_sddcs and @@all_sddcs[credentials]
          return @@all_sddcs[credentials]
        end
        habitats = []
        org = VMC.getOrg(credentials)
        if org and org['id']
          sddcs = VMC.callAPI("orgs/"+org['id']+"/sddcs", credentials: credentials)
          habitats.concat(sddcs.map { |s| s['id'] })
        end
        @@all_sddcs[credentials] = habitats
        @@all_sddcs[credentials]
      end

      @@regions = {}
      # List all known regions
      # @param us_only [Boolean]: Restrict results to United States only
      def self.listRegions(us_only = false, credentials: nil)
# XXX not sure we'll even have a concept of regions in this layer, so return a single empty string for now
        [""]
      end

      def self.parseLibraryUrl(url, credentials: nil, habitat: nil)
        habitat ||= MU::Cloud::VMWare.defaultSDDC(credentials)

        library, path = url.split(/:/, 2)
        item, filename = path.sub(/^\/*/, '').split(/\//, 2)
        filename ||= item

        library_desc = MU::Cloud.resourceClass("VMWare", "Bucket").find(cloud_id: library, credentials: credentials, habitat: habitat).values.first

        if !library_desc
          raise MuError, "Failed to find a datastore matching #{url}"
        end

        item_id = MU::Cloud::VMWare.library_item(credentials: credentials, habitat: habitat).find(::VSphereAutomation::Content::ContentLibraryItemFind.new(
          spec: ::VSphereAutomation::Content::ContentLibraryItemFindSpec.new(
            name: item,
            library_id: library_desc.id
        ))).value.first

        [library, library_desc.id, item, item_id]
      end

      @@instance_types = nil
      # Query the GCP API for the list of valid Compute instance types and some of
      # their attributes. We can use this in config validation and to help
      # "translate" machine types across cloud providers.
      # @param region [String]: Supported machine types can vary from region to region, so we look for the set we're interested in specifically
      # @return [Hash]
      def self.listInstanceTypes(region = self.myRegion, credentials: nil, project: MU::Cloud::VMWare.defaultProject)
        {}
      end

      # List the Availability Zones associated with a given Google Cloud
      # region. If no region is given, search the one in which this MU master
      # server resides (if it resides in this cloud provider's ecosystem).
      # @param region [String]: The region to search.
      # @return [Array<String>]: The Availability Zones in this region.
      def self.listAZs(region = self.myRegion)
        []
      end

      @@vmc_endpoints = {}
      def self.vmc(credentials: nil, habitat: nil)
        habitat ||= defaultSDDC(credentials)
        @@vmc_endpoints[credentials] ||= {}
        @@vmc_endpoints[credentials][habitat] ||= VMC.new(credentials, habitat: habitat)
        @@vmc_endpoints[credentials][habitat]
      end

      @@nsx_endpoints = {}
      def self.nsx(credentials: nil, habitat: nil)
        habitat ||= defaultSDDC(credentials)
        @@nsx_endpoints[credentials] ||= {}
        @@nsx_endpoints[credentials][habitat] ||= NSX.new(credentials, habitat: habitat)
        @@nsx_endpoints[credentials][habitat]
      end

      def self.identity(credentials: nil, habitat: nil)
        VSphereEndpoint.new(api: "IdentityProvidersApi", credentials: credentials, habitat: habitat)
      end

      @@ovf_endpoints = {}
      def self.ovf(credentials: nil, habitat: nil)
        habitat ||= defaultSDDC(credentials)

        @@ovf_endpoints[credentials] ||= {}
        @@ovf_endpoints[credentials][habitat] ||= VSphereEndpoint.new(api: "OvfLibraryItemApi", credentials: credentials, habitat: habitat)
        @@ovf_endpoints[credentials][habitat]
      end

      @@library_endpoints = {}
      def self.library(credentials: nil, habitat: nil)
        habitat ||= defaultSDDC(credentials)
        @@library_endpoints[credentials] ||= {}
        @@library_endpoints[credentials][habitat] ||= VSphereEndpoint.new(api: "LibraryApi", credentials: credentials, habitat: habitat, section: :Content)
        @@library_endpoints[credentials][habitat]
      end

      @@library_file_endpoints = {}
      def self.library_file(credentials: nil, habitat: nil)
        habitat ||= defaultSDDC(credentials)
        @@library_file_endpoints[credentials] ||= {}
        @@library_file_endpoints[credentials][habitat] ||= VSphereEndpoint.new(api: "LibraryItemFileApi", credentials: credentials, habitat: habitat, section: :Content)
        @@library_file_endpoints[credentials][habitat]
      end

      @@library_file_session_endpoints = {}
      def self.library_file_session(credentials: nil, habitat: nil)
        habitat ||= defaultSDDC(credentials)
        @@library_file_session_endpoints[credentials] ||= {}
        @@library_file_session_endpoints[credentials][habitat] ||= VSphereEndpoint.new(api: "LibraryItemUpdatesessionFileApi", credentials: credentials, habitat: habitat, section: :Content)
        @@library_file_session_endpoints[credentials][habitat]
      end

      @@library_update_endpoints = {}
      def self.library_update(credentials: nil, habitat: nil)
        habitat ||= defaultSDDC(credentials)
        @@library_update_endpoints[credentials] ||= {}
        @@library_update_endpoints[credentials][habitat] ||= VSphereEndpoint.new(api: "LibraryItemUpdateSessionApi", credentials: credentials, habitat: habitat, section: :Content)
        @@library_update_endpoints[credentials][habitat]
      end

      @@library_item_endpoints = {}
      def self.library_item(credentials: nil, habitat: nil)
        habitat ||= defaultSDDC(credentials)
        @@library_item_endpoints[credentials] ||= {}
        @@library_item_endpoints[credentials][habitat] ||= VSphereEndpoint.new(api: "LibraryItemApi", credentials: credentials, habitat: habitat, section: :Content)
        @@library_item_endpoints[credentials][habitat]
      end

      @@subscribed_library_endpoints = {}
      def self.subscribed_library(credentials: nil, habitat: nil)
        habitat ||= defaultSDDC(credentials)
        @@subscribed_library_endpoints[credentials] ||= {}
        @@subscribed_library_endpoints[credentials][habitat] ||= VSphereEndpoint.new(api: "SubscribedLibraryApi", credentials: credentials, habitat: habitat, section: :Content)
        @@subscribed_library_endpoints[credentials][habitat]
      end

      @@local_library_endpoints = {}
      def self.local_library(credentials: nil, habitat: nil)
        habitat ||= defaultSDDC(credentials)
        @@local_library_endpoints[credentials] ||= {}
        @@local_library_endpoints[credentials][habitat] ||= VSphereEndpoint.new(api: "LocalLibraryApi", credentials: credentials, habitat: habitat, section: :Content)
        @@local_library_endpoints[credentials][habitat]
      end

      @@guest_endpoints = {}
      def self.guest(credentials: nil, habitat: nil)
        habitat ||= defaultSDDC(credentials)
        @@guest_endpoints[credentials] ||= {}
        @@guest_endpoints[credentials][habitat] ||= VSphereEndpoint.new(api: "VmGuestIdentityApi", credentials: credentials, habitat: habitat)
        @@guest_endpoints[credentials][habitat]
      end

      @@guest_processes_endpoints = {}
      def self.guest_processes(credentials: nil, habitat: nil)
        habitat ||= defaultSDDC(credentials)
        @@guest_processes_endpoints[credentials] ||= {}
        @@guest_processes_endpoints[credentials][habitat] ||= VSphereEndpoint.new(api: "VmGuestProcessesApi", credentials: credentials, habitat: habitat, debug: true)
        @@guest_processes_endpoints[credentials][habitat]
      end

      @@datacenter_endpoints = {}
      def self.datacenter(credentials: nil, habitat: nil)
        habitat ||= defaultSDDC(credentials)
        @@datacenter_endpoints[credentials] ||= {}
        @@datacenter_endpoints[credentials][habitat] ||= VSphereEndpoint.new(api: "DatacenterApi", credentials: credentials, habitat: habitat)
        @@datacenter_endpoints[credentials][habitat]
      end

      @@datastore_endpoints = {}
      def self.datastore(credentials: nil, habitat: nil)
        habitat ||= defaultSDDC(credentials)
        @@datastore_endpoints[credentials] ||= {}
        @@datastore_endpoints[credentials][habitat] ||= VSphereEndpoint.new(api: "DatastoreApi", credentials: credentials, habitat: habitat)
        @@datastore_endpoints[credentials][habitat]
      end

      @@resource_pool_endpoints = {}
      def self.resource_pool(credentials: nil, habitat: nil)
        habitat ||= defaultSDDC(credentials)
        @@resource_pool_endpoints[credentials] ||= {}
        @@resource_pool_endpoints[credentials][habitat] ||= VSphereEndpoint.new(api: "ResourcePoolApi", credentials: credentials, habitat: habitat)
        @@resource_pool_endpoints[credentials][habitat]
      end

      @@network_endpoints = {}
      def self.network(credentials: nil, habitat: nil)
        habitat ||= defaultSDDC(credentials)
        @@network_endpoints[credentials] ||= {}
        @@network_endpoints[credentials][habitat] ||= VSphereEndpoint.new(api: "NetworkApi", credentials: credentials, habitat: habitat)
        @@network_endpoints[credentials][habitat]
      end

      @@folder_endpoints = {}
      def self.folder(credentials: nil, habitat: nil)
        habitat ||= defaultSDDC(credentials)
        @@folder_endpoints[credentials] ||= {}
        @@folder_endpoints[credentials][habitat] ||= VSphereEndpoint.new(api: "FolderApi", credentials: credentials, habitat: habitat)
        @@folder_endpoints[credentials][habitat]
      end

      @@datastore_endpoints = {}
      def self.datastore(credentials: nil, habitat: nil)
        habitat ||= defaultSDDC(credentials)
        @@datastore_endpoints[credentials] ||= {}
        @@datastore_endpoints[credentials][habitat] ||= VSphereEndpoint.new(api: "DatastoreApi", credentials: credentials, habitat: habitat)
        @@datastore_endpoints[credentials][habitat]
      end

      @@power_endpoints = {}
      def self.power(credentials: nil, habitat: nil)
        habitat ||= defaultSDDC(credentials)
        @@power_endpoints[credentials] ||= {}
        @@power_endpoints[credentials][habitat] ||= VSphereEndpoint.new(api: "VmPowerApi", credentials: credentials, habitat: habitat)
        @@power_endpoints[credentials][habitat]
      end

      @@vm_endpoints = {}
      def self.vm(credentials: nil, habitat: nil)
        habitat ||= defaultSDDC(credentials)
        @@vm_endpoints[credentials] ||= {}
        @@vm_endpoints[credentials][habitat] ||= VSphereEndpoint.new(api: "VMApi", credentials: credentials, habitat: habitat)
        @@vm_endpoints[credentials][habitat]
      end

      @@host_endpoints = {}
      def self.host(credentials: nil, habitat: nil)
        habitat ||= defaultSDDC(credentials)
        @@host_endpoints[credentials] ||= {}
        @@host_endpoints[credentials][habitat] ||= VSphereEndpoint.new(api: "HostApi", credentials: credentials, habitat: habitat)
        @@host_endpoints[credentials][habitat]
      end

      @@cluster_endpoints = {}
      def self.cluster(credentials: nil, habitat: nil)
        habitat ||= defaultSDDC(credentials)
        @@cluster_endpoints[credentials] ||= {}
        @@cluster_endpoints[credentials][habitat] ||= VSphereEndpoint.new(api: "ClusterApi", credentials: credentials, habitat: habitat)
        @@cluster_endpoints[credentials][habitat]
      end

      # Wrapper class for vSphere APIs, so that we can catch some common
      # transient endpoint errors without having to spray rescues all over the
      # codebase.
      class VSphereEndpoint
        attr_reader :org
        attr_reader :api
        attr_reader :credentials
        attr_reader :session_key

        @credentials = nil

        # Create a vSphere API client
        # @param api [String]: Which API are we wrapping?
        # @param scopes [Array<String>]: Google auth scopes applicable to this API
        def initialize(api: "esx", section: :VCenter, credentials: nil, habitat: nil, debug: false)
          @credentials = credentials
          @org = VMC.getOrg(@credentials)['id']
          @api = api.to_sym
          @habitat = habitat
          @habitat ||= MU::Cloud::VMWare.defaultSDDC(credentials)

          @sddc = MU::Cloud.resourceClass("VMWare", "Habitat").find(credentials: @credentials, cloud_id: @habitat).values.first
          if !@sddc
            raise MuError.new "Couldn't load details for my native SDDC", details: { "credentials" => @credentials, "org" => @org, "habitat" => @habitat }
          end

          url, cert = if api == "nsx"
            [@sddc["resource_config"]["nsx_mgr_url"], @sddc["resource_config"]["certificates"]["NSX_MANAGER"]]
          else
            [@sddc["resource_config"]["vc_url"], @sddc["resource_config"]["certificates"]["VCENTER"]]
          end
# ["resource_config"]["cloud_username"]
# ["resource_config"]["cloud_password"]
          configuration = VSphereAutomation::Configuration.new.tap do |c|
            c.host = url
            c.username = @sddc["resource_config"]["cloud_username"]
            c.password = @sddc["resource_config"]["cloud_password"]
            c.debugging = debug
#            c.cert_file = StringIO.new(cert["certificate"])
            c.scheme = 'https'
          end

          @api_blob = VSphereAutomation::ApiClient.new(configuration)
          @session = VSphereAutomation::CIS::SessionApi.new(@api_blob).create('')
          @session_key = @session.value
          @api_client = VSphereAutomation.const_get(section).const_get(@api).new(@api_blob)

        end

        # Catch-all for AWS client methods. Essentially a pass-through with some
        # rescues for known silly endpoint behavior.
        def method_missing(method_sym, *arguments)
          resp = nil
          MU.retrier([VSphereError, Errno::EBADF, IOError], max: 6, wait: 5) {
            resp = if arguments and !arguments.empty?
              @api_client.send(method_sym, *arguments)
            else
              @api_client.send(method_sym)
            end
            if resp.is_a?(VSphereAutomation::VCenter::VapiStdErrorsServiceUnavailableError)
              raise VSphereError.new "vSphere API error calling #{api}.#{method_sym}: #{resp.value.error_type}", details: resp.value.messages
            end
          }
          resp
        end

      end

    end
  end
end
