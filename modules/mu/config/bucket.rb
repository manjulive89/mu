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
  class Config
    # Basket of Kittens config schema and parser logic. See modules/mu/clouds/*/bucket.rb
    class Bucket

      # Base configuration schema for a Bucket
      # @return [Hash]
      def self.schema
        {
          "type" => "object",
          "additionalProperties" => false,
          "description" => "A simple storage bucket, like Google Cloud Storage or Amazon S3.",
          "properties" => {
            "name" => {
              "type" => "string"
            },
            "region" => MU::Config.region_primitive,
            "credentials" => MU::Config.credentials_primitive,
            "versioning" => {
              "type" => "boolean",
              "default" => false,
              "description" => "Enable object versioning on this bucket."
            },
            "web" => {
              "type" => "boolean",
              "default" => false,
              "description" => "Enable web service on this bucket."
            },
            "web_error_object" => {
              "type" => "string",
              "default" => "error.html",
              "description" => "If +web_enabled+, return this object for error conditions (such as a +404+) supported by the cloud provider."
            },
            "web_index_object" => {
              "type" => "string",
              "default" => "index.html",
              "description" => "If +web_enabled+, return this object when \"diretory\" (a path not ending in a key/object) is invoked."
            },
            "policies" => {
              "type" => "array",
              "items" => MU::Config::Role.policy_primitive(subobjects: true, grant_to: true, permissions_optional: true)
            }
          }
        }
      end

      # Generic pre-processing of {MU::Config::BasketofKittens::buckets}, bare and unvalidated.
      # @param bucket [Hash]: The resource to process and validate
      # @param configurator [MU::Config]: The overall deployment configurator of which this resource is a member
      # @return [Boolean]: True if validation succeeded, False otherwise
      def self.validate(bucket, configurator)
        ok = true

        ok
      end

    end
  end
end