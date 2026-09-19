require 'spec_helper'

# Container is run in web mode with SVC_SMOKESCREEN_ENABLED=false (explicit
# operator override) and DISABLE_DESKPRO_PROXY_SERVICE unset (see Earthfile
# test-smokescreen target). The explicit SVC_SMOKESCREEN_ENABLED wins for the
# daemon even though the run mode would otherwise derive it on -- but since
# DISABLE_DESKPRO_PROXY_SERVICE is unset, the proxy env vars are still
# exported (DISABLE is the only thing that controls them).
describe "explicit SVC_SMOKESCREEN_ENABLED=false stops the daemon without touching the proxy env vars" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe process('smokescreen') do
    it { should_not be_running }
  end

  describe file('/etc/supervisor/conf.d/smokescreen.conf') do
    its(:content) { should include "autostart=false" }
  end

  it "still embeds the proxy vars into the php_fpm program's environment" do
    content = File.read('/etc/supervisor/conf.d/web.conf')
    php_fpm_block = content.split('[program:').find { |b| b.start_with?('php_fpm]') }
    expect(php_fpm_block).to include 'HTTP_PROXY="http://127.0.0.1:3128"'
  end
end
