require 'spec_helper'

# Default (web mode, no overrides): the egress proxy is off -- the daemon is
# not started and no proxy env vars are exported, so outbound goes direct.
# Opt in with DISABLE_DESKPRO_PROXY_SERVICE=false (covered by
# spec/scenarios/smokescreen/13_smokescreen_enabled_spec.rb).
describe "smokescreen egress proxy: off by default" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe process('smokescreen') do
    it { should_not be_running }
  end

  describe file('/etc/supervisor/conf.d/smokescreen.conf') do
    its(:content) { should include "autostart=false" }
  end

  it "does not listen on the proxy port" do
    output = `ss -tlnp 2>/dev/null || netstat -tln 2>/dev/null`
    expect(output).not_to include ":3128"
  end

  it "does not embed the proxy vars into php_fpm's environment" do
    content = File.read('/etc/supervisor/conf.d/web.conf')
    php_fpm_block = content.split('[program:').find { |b| b.start_with?('php_fpm]') }
    expect(php_fpm_block).to include 'HTTP_PROXY=""'
    expect(php_fpm_block).not_to include 'HTTP_PROXY="http://127.0.0.1:3128"'
    expect(php_fpm_block).not_to include 'NO_PROXY="localhost'
  end
end
