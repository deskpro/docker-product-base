require 'spec_helper'

# Container is run with DISABLE_DESKPRO_PROXY_SERVICE=false AND
# DESKPRO_HTTPS_PROXY=http://egress.example:3128 (see Earthfile
# test-smokescreen target). Both set: the DESKPRO value wins on the app
# services for the variable it covers; the smokescreen value remains the
# fallback for the others, and the daemon still runs.
describe "DESKPRO_*_PROXY takes precedence over smokescreen on the app services" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  ext = 'http://egress.example:3128'

  describe process('smokescreen') do
    it { should be_running }
  end

  %w[web tasks email messenger].each do |n|
    describe file("/etc/supervisor/conf.d/#{n}.conf") do
      its(:content) { should include %(HTTPS_PROXY="#{ext}") }
      its(:content) { should include %(https_proxy="#{ext}") }
      its(:content) { should include 'HTTP_PROXY="http://127.0.0.1:3128"' }
      its(:content) { should include 'ALL_PROXY="http://127.0.0.1:3128"' }
      its(:content) { should match(/NO_PROXY="[^"]*localhost[^"]*"/) }
    end
  end
end
