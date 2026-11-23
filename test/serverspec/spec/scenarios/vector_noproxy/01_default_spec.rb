require 'spec_helper'

# Container run with HTTP_PROXY set and LOGS_EXPORT_TARGET=cloudwatch (see
# Earthfile test-vector-noproxy), no override.
describe "vector cloudwatch sink bypasses the ambient HTTP_PROXY" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe command('printenv HTTP_PROXY') do
    its(:exit_status) { should eq 0 }
  end

  describe file('/etc/vector/vector.d/90-output.toml') do
    # sink block = from its header up to the next [section] header
    its(:content) { should match /^\[sinks\.out_cloudwatch_logs\]\n(?:(?!\[).*\n)*?proxy\.enabled = false$/ }
  end

  # the key must be accepted by this vector version
  describe command('vector validate --no-environment /etc/vector/vector.toml /etc/vector/vector.d/*.toml') do
    its(:exit_status) { should eq 0 }
  end
end
