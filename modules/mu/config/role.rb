# Copyright:: Copyright (c) 2018 eGlobalTech, Inc., all rights reserved
#
# Licensed under the BSD-3 license (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License in the root of the folder or at
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
    # Basket of Kittens config schema and parser logic. See modules/mu/clouds/*/role.rb
    class Role

      # Base configuration schema for a Group
      # @return [Hash]
      def self.schema
        {
          "type" => "object",
          "additionalProperties" => false,
          "description" => "Set up a cloud provider role for mapping permissions to other entities",
          "properties" => {
            "name" => {
              "type" => "string",
              "description" => "The name of a cloud provider role to create"
            },
            "policies" => {
              "type" => "array",
              "items" => {
                "type" => "object",
                "description" => "A policy to grant or deny permissions.",
                "required" => ["permissions"],
                "additionalProperties" => false,
                "properties" => {
                  "flag" => {
                    "type" => "string",
                    "enum" => ["allow", "deny"],
                    "default" => "allow"
                  },
                  "permissions" => {
                    "type" => "array",
                    "items" => {
                      "type" => "string",
                      "description" => "Permissions to grant or deny. Valid permission strings are cloud-specific."
                    }
                  },
                  "targets" => {
                    "type" => "array",
                    "items" => {
                      "type" => "object",
                      "description" => "Entities to which this policy will grant or deny access.",
                      "required" => ["identifier"],
                      "additionalProperties" => false,
                      "properties" => {
                        "type" => {
                          "type" => "string",
                          "description" => "A Mu resource type, used when referencing a sibling Mu resource in this stack with +identifier+.",
                          "enum" => MU::Cloud.resource_types.values.map { |t| t[:cfg_name] }
                        },
                        "identifier" => {
                          "type" => "string",
                          "description" => "Either the name of a sibling Mu resource in this stack (used in conjunction with +entity_type+), or the full cloud identifier for a resource, such as an ARN in Amazon Web Services."
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      end

      # Generic pre-processing of {MU::Config::BasketofKittens::role}, bare and unvalidated.
      # @param role [Hash]: The resource to process and validate
      # @param configurator [MU::Config]: The overall deployment configurator of which this resource is a member
      # @return [Boolean]: True if validation succeeded, False otherwise
      def self.validate(role, configurator)
        ok = true
        ok
      end

    end
  end
end
