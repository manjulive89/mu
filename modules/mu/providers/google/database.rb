# Copyright:: Copyright (c) 2014 eGlobalTech, Inc., all rights reserved
#
# Licensed under the BSD-3 license (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License in the root of the project or at
#
#	http://egt-labs.com/mu/LICENSE.html
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

module MU
  class Cloud
    class Google
      # A database as configured in {MU::Config::BasketofKittens::databases}
      class Database < MU::Cloud::Database

        # Initialize this cloud resource object. Calling +super+ will invoke the initializer defined under {MU::Cloud}, which should set the attribtues listed in {MU::Cloud::PUBLIC_ATTRS} as well as applicable dependency shortcuts, like <tt>@vpc</tt>, for us.
        # @param args [Hash]: Hash of named arguments passed via Ruby's double-splat
        def initialize(**args)
          super
          @config["groomer"] = MU::Config.defaultGroomer unless @config["groomer"]
          @groomclass = MU::Groomer.loadGroomer(@config["groomer"])

          @mu_name ||= @deploy.getResourceName(@config["name"], max_length: 63)
        end

        # Called automatically by {MU::Deploy#createResources}
        # @return [String]: The cloud provider's identifier for this database instance.
        def create
          @project_id = MU::Cloud::Google.projectLookup(@config['project'], @deploy).cloud_id
          labels = {}
          MU::MommaCat.listStandardTags.each_pair { |name, value|
            if !value.nil?
              labels[name.downcase] = value.downcase.gsub(/[^a-z0-9\-\_]/i, "_")
            end
          }
          labels["name"] = MU::Cloud::Google.nameStr(@mu_name)

          settings = MU::Cloud::Google.sql(:Settings).new(
            user_labels: labels,
#            data_disk_size_gb: @config['storage'],
            tier: "D0" # XXX this is instance size, basically
          )
          instance_desc = MU::Cloud::Google.sql(:DatabaseInstance).new(
            name: MU::Cloud::Google.nameStr(@mu_name),
            settings: settings,
#            backend_type: "SECOND_GEN",
            description: @deploy.deploy_id,
            database_version: "MYSQL_5_6", # TODO construct from config
#            region: "us-central1", # XXX super restricted, this
            instance_type: "CLOUD_SQL_INSTANCE" # TODO: READ_REPLICA_INSTANCE
          )
          pp instance_desc
          pp MU::Cloud::Google.sql(credentials: @config['credentials']).insert_instance(@project_id, instance_desc)
        end

        # Locate an existing Database or Databases and return an array containing matching GCP resource descriptors for those that match.
        # @return [Array<Hash<String,OpenStruct>>]: The cloud provider's complete descriptions of matching Databases
        def self.find(**args)
          args = MU::Cloud::Google.findLocationArgs(args)
        end

        # Called automatically by {MU::Deploy#createResources}
        def groom
          @project_id = MU::Cloud::Google.projectLookup(@config['project'], @deploy).cloud_id
        end

        # Register a description of this database instance with this deployment's metadata.
        # Register read replicas as separate instances, while we're
        # at it.
        def notify
        end

        # Permit a host to connect to the given database instance.
        # @param cidr [String]: The CIDR-formatted IP address or block to allow access.
        # @return [void]
        def allowHost(cidr)
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

        # Called by {MU::Cleanup}. Locates resources that were created by the
        # currently-loaded deployment, and purges them.
        # @param noop [Boolean]: If true, will only print what would be done
        # @param ignoremaster [Boolean]: If true, will remove resources not flagged as originating from this Mu server
        # @param region [String]: The cloud provider region in which to operate
        # @return [void]
        def self.cleanup(noop: false, ignoremaster: false, region: MU.curRegion, credentials: nil, flags: {})
          flags["habitat"] ||= MU::Cloud::Google.defaultProject(credentials)

#          instances = MU::Cloud::Google.sql(credentials: credentials).list_instances(flags['habitat'], filter: %Q{userLabels.mu-id:"#{MU.deploy_id.downcase}"})
#          if instances and instances.items
#            instances.items.each { |instance|
#              MU.log "Deleting Cloud SQL instance #{instance.name}"
#              MU::Cloud::Google.sql(credentials: credentials).delete_instance(flags['habitat'], instance.name) if !noop
#            }
#          end
        end

        # Cloud-specific configuration properties.
        # @param _config [MU::Config]: The calling MU::Config object
        # @return [Array<Array,Hash>]: List of required fields, and json-schema Hash of cloud-specific configuration parameters for this resource
        def self.schema(_config)
          toplevel_required = []
          schema = {}
          [toplevel_required, schema]
        end

        # Cloud-specific pre-processing of {MU::Config::BasketofKittens::databases}, bare and unvalidated.
        # @param db [Hash]: The resource to process and validate
        # @param _configurator [MU::Config]: The overall deployment configurator of which this resource is a member
        # @return [Boolean]: True if validation succeeded, False otherwise
        def self.validateConfig(db, _configurator)
          ok = true

          if db["create_cluster"]
            MU.log "Database clusters not currently available in Google Cloud". MU::ERR
            ok = false
          end

          ok
        end

      end #class
    end #class
  end
end #module
