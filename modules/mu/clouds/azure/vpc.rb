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

module MU
  class Cloud
    class Azure

      # Creation of Virtual Private Clouds and associated artifacts (routes, subnets, etc).
      class VPC < MU::Cloud::VPC

        @deploy = nil
        @config = nil
        attr_reader :mu_name
        attr_reader :cloud_id
        attr_reader :url
        attr_reader :config
        attr_reader :cloud_desc_cache

        # @param mommacat [MU::MommaCat]: A {MU::Mommacat} object containing the deploy of which this resource is/will be a member.
        # @param kitten_cfg [Hash]: The fully parsed and resolved {MU::Config} resource descriptor as defined in {MU::Config::BasketofKittens::vpcs}
        def initialize(mommacat: nil, kitten_cfg: nil, mu_name: nil, cloud_id: nil)
          @deploy = mommacat
          @config = MU::Config.manxify(kitten_cfg)
          @subnets = []
          @subnetcachesemaphore = Mutex.new

          if !mu_name.nil?
            @mu_name = mu_name
            loadSubnets(use_cache: true)
          elsif @config['scrub_mu_isms']
            @mu_name = @config['name']
          else
            @mu_name = @deploy.getResourceName(@config['name'])
          end

        end

        # Called automatically by {MU::Deploy#createResources}
        def create
          create_update
        end


        # Called automatically by {MU::Deploy#createResources}
        def groom
          create_update

# XXX peering goes here
        end

        # Describe this VPC
        # @return [Hash]
        def notify
          base = {}
          base = MU.structToHash(cloud_desc)
          base["cloud_id"] = @mu_name
          base.merge!(@config.to_h)
#          if @subnets
#            base["subnets"] = @subnets.map { |s| s.notify }
#          end
          base
        end
#
        # Describe this VPC from the cloud platform's perspective
        # @return [Hash]
        def cloud_desc
          if @cloud_desc_cache
            return @cloud_desc_cache
          end
          desc = MU::Cloud::Azure::VPC.find(cloud_id: @mu_name).values.first

# XXX bolt on routes, subnets, etc

          @cloud_desc_cache = desc
        end

        # Locate an existing VPC or VPCs and return an array containing matching Azure cloud resource descriptors for those that match.
        # @param cloud_id [String]: The cloud provider's identifier for this resource.
        # @param region [String]: The cloud provider region
        # @param tag_key [String]: A tag key to search.
        # @param tag_value [String]: The value of the tag specified by tag_key to match when searching by tag.
        # @return [Array<Hash<String,OpenStruct>>]: The cloud provider's complete descriptions of matching VPCs
        def self.find(**args)
          found = {}

          # Azure resources are namedspaced by resource group. If we weren't
          # told one, we may have to search all the ones we can see.
          resource_groups = if args[:resource_group]
            [args[:resource_group]]
          elsif args[:cloud_id] and args[:cloud_id].is_a?(MU::Cloud::Azure::Id)
            [args[:cloud_id].resource_group]
          else
            MU::Cloud::Azure.resources(credentials: args[:credentials]).resource_groups.list.map { |rg| rg.name }
          end

          if args[:cloud_id]
            id_str = args[:cloud_id].is_a?(MU::Cloud::Azure::Id) ? args[:cloud_id].name : args[:cloud_id]
            resource_groups.each { |rg|
              begin
                resp = MU::Cloud::Azure.network(credentials: args[:credentials]).virtual_networks.get(rg, id_str)
                found[Id.new(resp.id)] = resp
              rescue MsRestAzure::AzureOperationError => e
                # this is fine, we're doing a blind search after all
              end
            }
          else
            if args[:resource_group]
              MU::Cloud::Azure.network(credentials: args[:credentials]).virtual_networks.list(args[:resource_group]).each { |net|
                found[Id.new(resp.id)] = net
              }
            else
              MU::Cloud::Azure.network(credentials: args[:credentials]).virtual_networks.list_all.each { |net|
                found[Id.new(resp.id)] = net
              }
            end
          end

          found
        end

        # Return an array of MU::Cloud::Azure::VPC::Subnet objects describe the
        # member subnets of this VPC.
        #
        # @return [Array<MU::Cloud::Azure::VPC::Subnet>]
        def subnets
          if @subnets.nil? or @subnets.size == 0
            return loadSubnets
          end
          return @subnets
        end

        # Describe subnets associated with this VPC. We'll compose identifying
        # information similar to what MU::Cloud.describe builds for first-class
        # resources.
        # @param use_cache [Boolean]: If available, use saved deployment metadata to describe subnets, instead of querying the cloud API
        # @return [Array<Hash>]: A list of cloud provider identifiers of subnets associated with this VPC.
        def loadSubnets(use_cache: false)
          return @subnets
        end

        # Given some search criteria try locating a NAT Gaateway in this VPC.
        # @param nat_cloud_id [String]: The cloud provider's identifier for this NAT.
        # @param nat_filter_key [String]: A cloud provider filter to help identify the resource, used in conjunction with nat_filter_value.
        # @param nat_filter_value [String]: A cloud provider filter to help identify the resource, used in conjunction with nat_filter_key.
        # @param region [String]: The cloud provider region of the target instance.
        def findNat(nat_cloud_id: nil, nat_filter_key: nil, nat_filter_value: nil, region: MU.curRegion)
          nil
        end

        # Given some search criteria for a {MU::Cloud::Server}, see if we can
        # locate a NAT host in this VPC.
        # @param nat_name [String]: The name of the resource as defined in its 'name' Basket of Kittens field, typically used in conjunction with deploy_id.
        # @param nat_cloud_id [String]: The cloud provider's identifier for this NAT.
        # @param nat_tag_key [String]: A cloud provider tag to help identify the resource, used in conjunction with tag_value.
        # @param nat_tag_value [String]: A cloud provider tag to help identify the resource, used in conjunction with tag_key.
        # @param nat_ip [String]: An IP address associated with the NAT instance.
        def findBastion(nat_name: nil, nat_cloud_id: nil, nat_tag_key: nil, nat_tag_value: nil, nat_ip: nil)
          nil
        end

        # Check for a subnet in this VPC matching one or more of the specified
        # criteria, and return it if found.
        def getSubnet(cloud_id: nil, name: nil, tag_key: nil, tag_value: nil, ip_block: nil)
          loadSubnets
          if !cloud_id.nil? and cloud_id.match(/^https:\/\//)
            cloud_id.gsub!(/.*?\//, "")
          end
          MU.log "getSubnet(cloud_id: #{cloud_id}, name: #{name}, tag_key: #{tag_key}, tag_value: #{tag_value}, ip_block: #{ip_block})", MU::DEBUG, details: caller[0]

          @subnets.each { |subnet|
            if !cloud_id.nil? and !subnet.cloud_id.nil? and subnet.cloud_id.to_s == cloud_id.to_s
              return subnet
            elsif !name.nil? and !subnet.name.nil? and subnet.name.to_s == name.to_s
              return subnet
            end
          }
          return nil
        end

        @route_cache = {}
        @rtb_cache = {}
        @rtb_cache_semaphore = Mutex.new
        # Check whether we (the Mu Master) have a direct route to a particular
        # instance. Useful for skipping hops through bastion hosts to get
        # directly at child nodes in peered VPCs, the public internet, and the
        # like.
        # @param target_instance [OpenStruct]: The cloud descriptor of the instance to check.
        # @param region [String]: The cloud provider region of the target subnet.
        # @return [Boolean]
        def self.haveRouteToInstance?(target_instance, region: MU.curRegion, credentials: nil)
          false
        end


        # Does this resource type exist as a global (cloud-wide) artifact, or
        # is it localized to a region/zone?
        # @return [Boolean]
        def self.isGlobal?
          false
        end

        # Denote whether this resource implementation is experiment, ready for
        # testing, or ready for production use.
        def self.quality
          MU::Cloud::ALPHA
        end

        # Remove all VPC resources associated with the currently loaded deployment.
        # @param noop [Boolean]: If true, will only print what would be done
        # @param ignoremaster [Boolean]: If true, will remove resources not flagged as originating from this Mu server
        # @param region [String]: The cloud provider region
        # @return [void]
        def self.cleanup(noop: false, ignoremaster: false, region: MU.curRegion, credentials: nil, flags: {})
        end

        # Reverse-map our cloud description into a runnable config hash.
        # We assume that any values we have in +@config+ are placeholders, and
        # calculate our own accordingly based on what's live in the cloud.
        # XXX add flag to return the diff between @config and live cloud
        def toKitten(rootparent: nil, billing: nil)
          return nil if cloud_desc.name == "default" # parent project builds these
          bok = {
            "cloud" => "Azure",
            "project" => @config['project'],
            "credentials" => @config['credentials']
          }

          bok
        end

        # Cloud-specific configuration properties.
        # @param config [MU::Config]: The calling MU::Config object
        # @return [Array<Array,Hash>]: List of required fields, and json-schema Hash of cloud-specific configuration parameters for this resource
        def self.schema(config = nil)
          toplevel_required = []
          schema = {
          }
          [toplevel_required, schema]
        end


        # Cloud-specific pre-processing of {MU::Config::BasketofKittens::vpcs}, bare and unvalidated.
        # @param vpc [Hash]: The resource to process and validate
        # @param configurator [MU::Config]: The overall deployment configurator of which this resource is a member
        # @return [Boolean]: True if validation succeeded, False otherwise
        def self.validateConfig(vpc, configurator)
          ok = true

          if (!vpc['route_tables'] or vpc['route_tables'].size == 0) and vpc['create_standard_subnets']
            vpc['route_tables'] = [
              {
                "name" => "internet",
                "routes" => [ { "destination_network" => "0.0.0.0/0", "gateway" => "#INTERNET" } ]
              },
              {
                "name" => "private",
                "routes" => [ { "destination_network" => "0.0.0.0/0", "gateway" => "#NAT" } ]
              }
            ]
          end

          if vpc['subnets']
            vpc['subnets'].each { |subnet|
              subnet_routes[subnet['route_table']] = Array.new if subnet_routes[subnet['route_table']].nil?
              subnet_routes[subnet['route_table']] << subnet['name']
            }
          end

          if (!vpc['subnets'] or vpc['subnets'].empty?) and vpc['create_standard_subnets']
            subnets = configurator.divideNetwork(vpc['ip_block'], vpc['route_tables'].size, 28)
            vpc['subnets'] ||= []
            vpc['route_tables'].each { |rtb|
              vpc['subnets'] << {
                "name" => "Subnet#{rtb['name'].capitalize}",
                "ip_block" => subnets.shift,
                "route_table" => rtb['name']
              }
            }

          end

          ok
        end

        # @param route [Hash]: A route description, per the Basket of Kittens schema
        # @param server [MU::Cloud::Azure::Server]: Instance to which this route will apply
        def createRouteForInstance(route, server)
          createRoute(route, network: @url, tags: [MU::Cloud::Azure.nameStr(server.mu_name)])
        end

        private

        def create_update
          @config['region'] ||= MU::Cloud::Azure.myRegion(@config['credentials'])
          tags = {}
          if !@config['scrub_mu_isms']
            tags = MU::MommaCat.listStandardTags
          end
          if @config['tags']
            @config['tags'].each { |tag|
              tags[tag['key']] = tag['value']
            }
          end

          vpc_obj =  MU::Cloud::Azure.network(:VirtualNetwork).new
          addr_space_obj = MU::Cloud::Azure.network(:AddressSpace).new
          addr_space_obj.address_prefixes = [
            @config['ip_block']
          ]
          vpc_obj.address_space = addr_space_obj
          vpc_obj.location = @config['region']
          vpc_obj.tags = tags

          rgroup_name = @deploy.deploy_id+"-"+@config['region'].upcase

          MU.log "Configuring VPC #{@mu_name} (#{@config['ip_block']}) in #{@config['region']}", details: vpc_obj
          resp = MU::Cloud::Azure.network(credentials: @config['credentials']).virtual_networks.create_or_update(
            rgroup_name,
            @mu_name,
            vpc_obj
          )

# this is slow: guard it and thread it
          rtb_map = {}
          @config['route_tables'].each { |rtb|
            rtb_name = @mu_name+"-"+rtb['name'].upcase
            rtb_obj = MU::Cloud::Azure.network(:RouteTable).new
            rtb_obj.location = @config['region']

            rtb_obj.tags = tags
            rtb_ref_obj = MU::Cloud::Azure.network(:RouteTable).new
            rtb_ref_obj.name = rtb_name
            rtb_map[rtb['name']] = rtb_ref_obj
            MU.log "Configuring route table #{rtb_name} in VPC #{@mu_name}", details: rtb_obj
            rtb_map[rtb['name']] = MU::Cloud::Azure.network(credentials: @config['credentials']).route_tables.create_or_update(
              rgroup_name,
              rtb_name,
              rtb_obj
            )

            rtb['routes'].each { |route|
              route_obj = MU::Cloud::Azure.network(:Route).new
              route_obj.address_prefix = route['destination_network']
              routename = rtb_name+"-"+route['destination_network'].gsub(/[^a-z0-9]/i, "_")
              route_obj.next_hop_type = if route['gateway'] == "#NAT"
                routename = rtb_name+"-NAT"
                "VirtualNetworkGateway"
              elsif route['gateway'] == "#INTERNET"
                routename = rtb_name+"-INTERNET"
                "Internet"
              else
                routename = rtb_name+"-LOCAL"
                "VnetLocal"
              end

# XXX ... or if it's an instance, I think we do VirtualAppliance and also set route_obj.next_hop_ip_address
#
#next_hop_type 'VirtualNetworkGateway', 'VnetLocal', 'Internet', 'VirtualAppliance', and 'None'. Possible values include: 'VirtualNetworkGateway', 'VnetLocal', 'Internet', 'VirtualAppliance', 'None'

              MU.log "Setting route #{routename} for #{route['destination_network']} in route table #{rtb_name}", details: rtb_obj
#              MU::Cloud::Azure.network(credentials: @config['credentials']).routes.create_or_update(
#                rgroup_name,
#                rtb_name,
#                routename,
#                route_obj
#              )

            }
          }

          @config['subnets'].each { |subnet|
            subnet_obj = MU::Cloud::Azure.network(:Subnet).new
            subnet_name = @mu_name+"-"+subnet['name'].upcase
            subnet_obj.address_prefix = subnet['ip_block']
            subnet_obj.route_table = rtb_map[subnet['route_table']]
            MU.log "Configuring subnet #{subnet_name} in VPC #{@mu_name}", details: subnet_obj
            MU::Cloud::Azure.network(credentials: @config['credentials']).subnets.create_or_update(
              rgroup_name,
              @mu_name,
              subnet_name,
              subnet_obj
            )
          }
        end

        protected

        # Subnets are almost a first-class resource. So let's kinda sorta treat
        # them like one. This should only be invoked on objects that already
        # exists in the cloud layer.
        class Subnet < MU::Cloud::Azure::VPC

          attr_reader :cloud_id
          attr_reader :url
          attr_reader :ip_block
          attr_reader :mu_name
          attr_reader :name
          attr_reader :cloud_desc_cache
          attr_reader :az

          # @param parent [MU::Cloud::Azure::VPC]: The parent VPC of this subnet.
          # @param config [Hash<String>]:
          def initialize(parent, config, precache_description: true)
            @parent = parent
            @config = MU::Config.manxify(config)
            @cloud_id = config['cloud_id']
            @url = config['url']
            @mu_name = config['mu_name']
            @name = config['name']
            @deploydata = config # This is a dummy for the sake of describe()
            @az = config['az']
            @ip_block = config['ip_block']
            @cloud_desc_cache = nil
            cloud_desc if precache_description
          end

          # Return the cloud identifier for the default route of this subnet.
          def defaultRoute
          end

          def notify
            cloud_desc.to_h
          end

          def cloud_desc
          end

          # Is this subnet privately-routable only, or public?
          # @return [Boolean]
          def private?
          end
        end

      end #class
    end #class
  end
end #module
