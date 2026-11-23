require 'spec_helper'

# As 01, with LOGS_EXPORT_CLOUDWATCH_PROXY_ENABLED=true.
describe "vector cloudwatch sink opt-in to the ambient HTTP_PROXY" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe command('printenv HTTP_PROXY') do
    its(:exit_status) { should eq 0 }
  end

  describe file('/etc/vector/vector.d/90-output.toml') do
    its(:content) { should match /^\[sinks\.out_cloudwatch_logs\]$/ }
    its(:content) { should_not match /^proxy\./ }
  end

  describe command('vector validate --no-environment /etc/vector/vector.toml /etc/vector/vector.d/*.toml') do
    its(:exit_status) { should eq 0 }
  end
end
