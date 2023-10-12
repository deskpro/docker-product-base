require 'spec_helper'

describe "Check installer ran when it should have" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe command('container-var AUTO_RUN_INSTALLER') do
    its(:stdout) { should contain "true" }
  end

  describe file('/var/log/docker-boot.log') do
    it { should exist }
    its(:content) { should contain "Running: bin/install" }
    its(:content) { should contain "Installer completed successfully" }
  end
end
