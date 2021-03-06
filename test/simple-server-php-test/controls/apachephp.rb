include_controls 'mu-tools-test'
node =json('/tmp/chef_node.json').params
control 'apache' do
    title 'This will test apache2 recipe'
	  %w(apache2 apache2-bin apache2-data apache2-utils).each do |pack|
      describe package(pack) do
        it { should be_installed }
      end
    end

  	describe service('apache2') do
	    it { should be_installed }
	    it { should be_enabled }
	    it { should be_running }
    end
end

control 'php' do 
  title 'This will test the php recipe'
	%w(php7.0).each do |pack|
    describe package(pack) do
      it { should be_installed }
    end
  end
end
