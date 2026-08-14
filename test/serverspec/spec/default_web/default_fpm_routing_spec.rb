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

  # NOTE: `contain` treats its argument as a regex, so it can't be used for these — `$` would be
  # read as an end-of-line anchor. `include` does a plain substring match on the content.
  describe file('/etc/nginx/conf.d/01-deskpro_setup.conf') do
    its(:content) { should include 'server unix:/run/php_fpm_dp_helpcenter.sock' }
    its(:content) { should include 'server unix:/run/php_fpm_dp_assets.sock' }
    its(:content) { should include 'map $request_uri $dpv5_web_backend' }

    # /file.php/<hash>/<name> is the blob/asset low script
    its(:content) { should include '"~/file\.php/" "dpv5_assets"' }
  end

  describe file('/etc/nginx/conf.d/deskpro_server_params') do
    its(:content) { should include 'fastcgi_pass $dpv5_web_backend;' }
  end

  # nginx must accept the rendered config, including the variable fastcgi_pass
  describe command('nginx -t') do
    its(:exit_status) { should eq 0 }
  end

  # vector scrapes these endpoints for per-pool metrics (see etc/vector/vector.d/10-php.toml.tmpl),
  # so they have to be in the 03-status.conf pool allowlist
  ['dp_helpcenter', 'dp_assets'].each do |pool|
    describe command("curl -sf 'http://127.0.0.1:10001/fpm/#{pool}/status?openmetrics'") do
      its(:exit_status) { should eq 0 }
      its(:stdout) { should include 'phpfpm_up 1' }
    end
  end
end
