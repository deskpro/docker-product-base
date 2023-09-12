require 'spec_helper'

describe "Check installer did not run when it should not" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe command('container-var AUTO_RUN_INSTALLER') do
    its(:stdout) { should contain "true" }
  end

  describe file('/var/log/docker-boot.log') do
    it { should exist }
    its(:content) { should contain "DB is up to date" }
    its(:content) { should_not contain "Running: bin/install" }
  end
end
