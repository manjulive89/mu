#
# Cookbook Name:: mu-utility
# Recipe:: ruby-1.9-fast
#
# Copyright:: Copyright (c) 2014 eGlobalTech, Inc., all rights reserved
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


bash "install ruby 1.9.3 private repo" do
  code <<-EOF

sudo add-apt-repository ppa:brightbox/ruby-ng-experimental
sudo apt-get -y update
sudo apt-get -y install ruby1.9.1 ruby1.9.1-dev
    
  EOF
end

