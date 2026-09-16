require 'spec_helper'

# Container is run with DISABLE_DESKPRO_PROXY_SERVICE=true (see Earthfile test-smokescreen target).
describe "DISABLE_DESKPRO_PROXY_SERVICE=true disables both the daemon and the proxy env vars" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe process('smokescreen') do
    it { should_not be_running }
  end

  describe file('/etc/supervisor/conf.d/smokescreen.conf') do
    its(:content) { should include "autostart=false" }
  end

  it "does not embed the proxy vars into the php_fpm program's environment" do
    content = File.read('/etc/supervisor/conf.d/web.conf')
    php_fpm_block = content.split('[program:').find { |b| b.start_with?('php_fpm]') }
    expect(php_fpm_block).to include 'HTTP_PROXY=""'
    expect(php_fpm_block).not_to include 'HTTP_PROXY="http://127.0.0.1:3128"'
  end
end
