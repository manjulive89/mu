# Copyright:: Copyright (c) 2019 eGlobalTech, Inc., all rights reserved
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
    class Google
      # Support for Google Cloud Storage
      class Bucket < MU::Cloud::Bucket
        @deploy = nil
        @config = nil

        attr_reader :mu_name
        attr_reader :config
        attr_reader :cloud_id

        # @param mommacat [MU::MommaCat]: A {MU::Mommacat} object containing the deploy of which this resource is/will be a member.
        # @param kitten_cfg [Hash]: The fully parsed and resolved {MU::Config} resource descriptor as defined in {MU::Config::BasketofKittens::logs}
        def initialize(mommacat: nil, kitten_cfg: nil, mu_name: nil, cloud_id: nil)
          @deploy = mommacat
          @config = MU::Config.manxify(kitten_cfg)
          @cloud_id ||= cloud_id
          @mu_name ||= @deploy.getResourceName(@config["name"])
        end

        # Called automatically by {MU::Deploy#createResources}
        def create
          MU::Cloud::Google.storage(credentials: credentials).insert_bucket(@config['project'], bucket_descriptor)
          @cloud_id = @mu_name.downcase
        end

        # Called automatically by {MU::Deploy#createResources}
        def groom
          current = cloud_desc
          changed = false

          if !current.versioning.enabled and @config['versioning']
            MU.log "Enabling versioning on Cloud Storage bucket #{@cloud_id}", MU::NOTICE
            changed = true
          elsif current.versioning.enabled and !@config['versioning']
            MU.log "Disabling versioning on Cloud Storage bucket #{@cloud_id}", MU::NOTICE
            changed = true
          end

          if current.website.nil? and @config['web']
            MU.log "Enabling website service on Cloud Storage bucket #{@cloud_id}", MU::NOTICE
            changed = true
          elsif !current.website.nil? and !@config['web']
            MU.log "Disabling website service on Cloud Storage bucket #{@cloud_id}", MU::NOTICE
            changed = true
          end

          if changed
            MU::Cloud::Google.storage(credentials: credentials).patch_bucket(@cloud_id, bucket_descriptor)
          end
        end

        # Does this resource type exist as a global (cloud-wide) artifact, or
        # is it localized to a region/zone?
        # @return [Boolean]
        def self.isGlobal?
          true
        end

        # Remove all buckets associated with the currently loaded deployment.
        # @param noop [Boolean]: If true, will only print what would be done
        # @param ignoremaster [Boolean]: If true, will remove resources not flagged as originating from this Mu server
        # @param region [String]: The cloud provider region
        # @return [void]
        def self.cleanup(noop: false, ignoremaster: false, region: MU.curRegion, credentials: nil, flags: {})
          flags["project"] ||= MU::Cloud::Google.defaultProject(credentials)

          resp = MU::Cloud::Google.storage(credentials: credentials).list_buckets(flags['project'])
          if resp and resp.items
            resp.items.each { |bucket|
              if bucket.labels and bucket.labels["mu-id"] == MU.deploy_id.downcase
                MU.log "Deleting Cloud Storage bucket #{bucket.name}"
                if !noop
                  MU::Cloud::Google.storage(credentials: credentials).delete_bucket(bucket.name)
                end
              end
            }
          end
        end

        # Return the metadata for this user cofiguration
        # @return [Hash]
        def notify
          MU.structToHash(cloud_desc)
        end

        # Locate an existing bucket.
        # @param cloud_id [String]: The cloud provider's identifier for this resource.
        # @param region [String]: The cloud provider region.
        # @param flags [Hash]: Optional flags
        # @return [OpenStruct]: The cloud provider's complete descriptions of matching bucket.
        def self.find(cloud_id: nil, region: MU.curRegion, credentials: nil, flags: {})
          found = {}
          if cloud_id
            found[cloud_id] = MU::Cloud::Google.storage(credentials: credentials).get_bucket(cloud_id)
          end
          found
        end

        # Cloud-specific configuration properties.
        # @param config [MU::Config]: The calling MU::Config object
        # @return [Array<Array,Hash>]: List of required fields, and json-schema Hash of cloud-specific configuration parameters for this resource
        def self.schema(config)
          toplevel_required = []
          schema = {
            "storage_class" => {
              "type" => "string",
              "enum" => ["MULTI_REGIONAL", "REGIONAL", "STANDARD", "NEARLINE", "COLDLINE", "DURABLE_REDUCED_AVAILABILITY"],
              "default" => "STANDARD"
            }
          }
          [toplevel_required, schema]
        end

        # Cloud-specific pre-processing of {MU::Config::BasketofKittens::bucket}, bare and unvalidated.

        # @param bucket [Hash]: The resource to process and validate
        # @param configurator [MU::Config]: The overall deployment configurator of which this resource is a member
        # @return [Boolean]: True if validation succeeded, False otherwise
        def self.validateConfig(bucket, configurator)
          ok = true

          ok
        end

        private

        # create and return the Google::Apis::StorageV1::Bucket object used by
        # both +insert_bucket+ and +patch_bucket+
        def bucket_descriptor
          labels = {}
          MU::MommaCat.listStandardTags.each_pair { |name, value|
            if !value.nil?
              labels[name.downcase] = value.downcase.gsub(/[^a-z0-9\-\_]/i, "_")
            end
          }
          labels["name"] = @mu_name.downcase

          params = {
            :name => @mu_name.downcase,
            :labels => labels,
            :storage_class => @config['storage_class'],
          }

          if @config['web']
            params[:website] = MU::Cloud::Google.storage(:Bucket)::Website.new(
              main_page_suffix: @config['web_index_object'],
              not_found_page: @config['web_error_object']
            )
          end

          if @config['versioning']
            params[:versioning] = MU::Cloud::Google.storage(:Bucket)::Versioning.new(enabled: true)
          else
            params[:versioning] = MU::Cloud::Google.storage(:Bucket)::Versioning.new(enabled: false)
          end

          MU::Cloud::Google.storage(:Bucket).new(params)
        end

      end
    end
  end
end