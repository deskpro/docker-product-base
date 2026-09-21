require 'spec_helper'

# Container is run with SMOKESCREEN_CONFIG_FILE pointing at a file mounted via
# /deskpro/config/smokescreen.d/ (see Earthfile test-smokescreen target). The
# fixture adds deny_ranges for an RFC 5737 TEST-NET-3 range that smokescreen
# does NOT block by default, so a live proxy request proves the operator's
# file content took effect -- not just that smokescreen didn't crash on it.
describe "Operator-provided smokescreen config takes effect" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe file('/etc/smokescreen/custom.yaml') do
    it { should exist }
  end

  describe file('/etc/supervisor/conf.d/smokescreen.conf') do
    its(:content) { should include "--config-file='/etc/smokescreen/custom.yaml'" }
    its(:content) { should include "autostart=true" }
  end

  describe process('smokescreen') do
    it { should be_running }
  end

  describe port(3128) do
    it { should be_listening }
  end

  it "denies the operator's extra deny_ranges entry, not just the built-in defaults" do
    headers = `curl -s -o /dev/null -D - -x http://127.0.0.1:3128 --max-time 3 'http://203.0.113.1/' 2>/dev/null`
    expect(headers).to match(/^HTTP\/[\d.]+ 407/)
    expect(headers).to include "Deny: User Configured"
  end
end
