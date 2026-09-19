require 'spec_helper'

# Container is run with DISABLE_DESKPRO_PROXY_SERVICE=true AND
# SVC_SMOKESCREEN_ENABLED=true (explicit operator override) (see Earthfile
# test-smokescreen target). An explicit SVC_SMOKESCREEN_ENABLED wins for the
# daemon regardless of DISABLE_DESKPRO_PROXY_SERVICE, which only controls the
# proxy env export -- so the daemon stays up while the env vars are still off.
describe "explicit SVC_SMOKESCREEN_ENABLED=true keeps the daemon up under DISABLE_DESKPRO_PROXY_SERVICE=true" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe process('smokescreen') do
    it { should be_running }
  end

  describe file('/etc/supervisor/conf.d/smokescreen.conf') do
    its(:content) { should include "autostart=true" }
  end

  describe port(3128) do
    it { should be_listening }
  end

  it "does not embed the proxy vars into the php_fpm program's environment" do
    content = File.read('/etc/supervisor/conf.d/web.conf')
    php_fpm_block = content.split('[program:').find { |b| b.start_with?('php_fpm]') }
    expect(php_fpm_block).to include 'HTTP_PROXY=""'
    expect(php_fpm_block).not_to include 'HTTP_PROXY="http://127.0.0.1:3128"'
  end
end
