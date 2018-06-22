name 'mu-glusterfs'
maintainer 'Ami Rahav'
maintainer_email 'amiram.rahav@eglobaltech.com'
license 'All rights reserved'
description 'Installs/Configures mu-glusterfs'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
source_url 'https://github.com/cloudamatic/mu'
issues_url 'https://github.com/cloudamatic/mu/issues'
chef_version '>= 12.1' if respond_to?(:chef_version)
version '0.1.0'
depends 'yum'
depends 'mu-firewall'
