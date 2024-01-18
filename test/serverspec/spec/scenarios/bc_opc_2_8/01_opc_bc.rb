require 'spec_helper'

describe "Check OPC config merging" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe file('/var/log/docker-boot.log') do
    it { should exist }
    its(:content) { should match /\[opc\] Detected OPC version 2\.8\.0/}
  end

  describe file('/srv/deskpro/INSTANCE_DATA/deskpro-config.d/01-deskpro-opc.php') do
    it { should exist }
  end

  describe command('/test_helper_tools/config_value database/host') do
    its(:stdout) { should contain "is_changed_value" }
  end

  describe command('/test_helper_tools/config_value database_advanced/read/host') do
    its(:stdout) { should contain "is_changed_value" }
  end

  describe command('/test_helper_tools/config_value elastic/hosts/0') do
    its(:stdout) { should contain "is_changed_value" }
  end

  describe command('/test_helper_tools/config_value paths/blobs_path') do
    its(:stdout) { should contain "is_changed_value" }
  end

  describe command('/test_helper_tools/config_value paths/var_path') do
    # NOT changed
    its(:stdout) { should contain "/srv/deskpro/INSTANCE_DATA/var" }
  end

  describe command('/test_helper_tools/config_value api_urls/base_url_private') do
    # NOT changed
    its(:stdout) { should contain "http://127.0.0.1:80" }
  end

  describe command('/test_helper_tools/config_value settings/core.filestorage_method') do
    its(:stdout) { should contain "is_changed_value" }
  end

  describe command('/test_helper_tools/config_value settings/api_auth.master_key') do
    its(:stdout) { should contain "is_changed_value" }
  end

  describe command('/test_helper_tools/config_value settings/arbitrary_key') do
    its(:stdout) { should contain "is_changed_value" }
  end

  describe command('/test_helper_tools/config_value app_settings/arbitrary_key') do
    its(:stdout) { should contain "is_changed_value" }
  end

  describe command('/test_helper_tools/config_value from_custom_file') do
    # from the config.custom.php file
    its(:stdout) { should contain "is_changed_value" }
  end
end
