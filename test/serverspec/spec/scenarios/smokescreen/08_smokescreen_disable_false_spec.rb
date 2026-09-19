require 'spec_helper'

# Container is run with DISABLE_DESKPRO_PROXY_SERVICE=false (explicit, not just
# unset/default) and no SVC_SMOKESCREEN_ENABLED override (see Earthfile
# test-smokescreen target). Baseline case: both the daemon and the proxy env
# vars stay on.
describe "DISABLE_DESKPRO_PROXY_SERVICE=false leaves both the daemon and the proxy env vars on" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe process('smokescreen') do
    it { should be_running }
  end

  describe file('/etc/supervisor/conf.d/smokescreen.conf') do
    its(:content) { should include "autostart=true" }
  end

  it "embeds the proxy vars into the php_fpm program's environment" do
    content = File.read('/etc/supervisor/conf.d/web.conf')
    php_fpm_block = content.split('[program:').find { |b| b.start_with?('php_fpm]') }
    expect(php_fpm_block).to include 'HTTP_PROXY="http://127.0.0.1:3128"'
  end
end
