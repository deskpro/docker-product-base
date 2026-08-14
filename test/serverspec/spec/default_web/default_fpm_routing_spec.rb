require 'spec_helper'

# The helpcenter (dpv5 "user" interface) and its /file.php/ blob+asset serving get their own
# FPM pools so they don't compete with the agent app for dp_default workers. nginx picks the
# pool with the $dpv5_web_backend map rendered into 01-deskpro_setup.conf.
describe "Check helpcenter / assets FPM pool routing" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe file('/run/php_fpm_dp_helpcenter.sock') do
    it { should exist }
    it { should be_socket }
  end

  describe file('/run/php_fpm_dp_assets.sock') do
    it { should exist }
    it { should be_socket }
  end

  describe file('/etc/nginx/conf.d/01-deskpro_setup.conf') do
    its(:content) { should contain "server unix:/run/php_fpm_dp_helpcenter.sock" }
    its(:content) { should contain "server unix:/run/php_fpm_dp_assets.sock" }
    its(:content) { should contain 'map $request_uri $dpv5_web_backend' }

    # /file.php/<hash>/<name> is the blob/asset low script
    its(:content) { should contain '"~/file\.php/" "dpv5_assets"' }
  end

  describe file('/etc/nginx/conf.d/deskpro_server_params') do
    its(:content) { should contain 'fastcgi_pass $dpv5_web_backend;' }
  end

  # nginx must accept the rendered config, including the variable fastcgi_pass
  describe command('nginx -t') do
    its(:exit_status) { should eq 0 }
  end
end
