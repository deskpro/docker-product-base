require 'spec_helper'

# Container is run with DISABLE_DESKPRO_PROXY_SERVICE=true (the default) plus
# DESKPRO_HTTPS_PROXY=http://egress.example:3128 and DESKPRO_DB_HOST=dbhost.internal
# (see Earthfile test-smokescreen target). External egress proxy path: the
# DESKPRO value reaches the app services, NO_PROXY is derived, and the
# in-container smokescreen daemon stays off.
describe "DESKPRO_*_PROXY external egress proxy with smokescreen off" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  ext = 'http://egress.example:3128'

  describe process('smokescreen') do
    it { should_not be_running }
  end

  describe file('/etc/supervisor/conf.d/smokescreen.conf') do
    its(:content) { should include "autostart=false" }
  end

  %w[web tasks email messenger].each do |n|
    describe file("/etc/supervisor/conf.d/#{n}.conf") do
      its(:content) { should include %(HTTPS_PROXY="#{ext}") }
      its(:content) { should include %(https_proxy="#{ext}") }
      its(:content) { should include 'HTTP_PROXY=""' }
      its(:content) { should include 'ALL_PROXY=""' }
      its(:content) { should_not include "127.0.0.1:3128" }
      its(:content) { should match(/NO_PROXY="[^"]*dbhost\.internal[^"]*"/) }
      its(:content) { should match(/NO_PROXY="[^"]*localhost[^"]*"/) }
      its(:content) { should match(/no_proxy="[^"]*dbhost\.internal[^"]*"/) }
    end
  end
end
