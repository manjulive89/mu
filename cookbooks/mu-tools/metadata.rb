name 'mu-tools'
maintainer 'Mu'
maintainer_email 'mu-developers@googlegroups.com'
license '# Copyright:: Copyright (c) 2014 eGlobalTech, Inc., all rights reserved
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
# limitations under the License.'
description 'Mu-specific platform capabilities'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
source_url 'https://github.com/cloudamatic/mu'
issues_url 'https://github.com/cloudamatic/mu/issues'
chef_version '>= 12.1' if respond_to?(:chef_version)
version '1.0.4'
depends "oracle-instantclient"
depends "nagios"
depends "database"
depends "postgresql"
depends "build-essential", '~> 8.0'
depends "mu-utility"
depends "java"
depends "windows", '= 3.2.0'
depends "mu-splunk"
depends "chef-vault"
depends "poise-python"
depends "yum-epel"
depends "mu-firewall"
depends "mu-activedirectory"
