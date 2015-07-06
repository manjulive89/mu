name             'mu-jenkins'
maintainer       'eGlobalTech, Inc'
maintainer_email 'mu-developers@googlegroups.com'
license          'All rights reserved'
description      'Installs/Configures mu-jenkins'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '0.2.0'
depends		 'java'
depends		 'jenkins'
depends		 'chef-vault'
depends		 'mu-utility'
