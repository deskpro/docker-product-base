require 'spec_helper'

describe "Check default PHP and PHP-FPM configurations" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  # default www pool should never exist
  describe file('/etc/php/8.3/fpm/pool.d/www.conf') do
    it { should_not exist }
  end

  describe file('/etc/php/8.3/fpm/pool.d/01-deskpro.conf') do
    it { should exist }
  end

  describe file('/etc/php/8.3/fpm/php-fpm.conf') do
    it { should exist }
  end

  describe file('/etc/php/8.3/fpm/php.ini') do
    it { should exist }
  end

  describe file('/etc/php/8.3/mods-available/deskpro.ini') do
    it { should exist }
  end

  describe file('/etc/php/8.3/fpm/conf.d/90-deskpro.ini') do
    it { should exist }
  end

  describe file('/etc/php/8.3/cli/conf.d/90-deskpro.ini') do
    it { should exist }
  end

  describe file('/etc/php/8.3/mods-available/deskpro-otel.ini') do
    it { should exist }
    its(:content) { should match /To enable opentelemetry/ }
  end

  describe php_config('date.timezone') do
    its(:value) { should eq 'UTC' }
  end

  describe php_config('memory_limit') do
    its(:value) { should eq '1G' }
  end

  describe php_config('expose_php') do
    its(:value) { should be_empty }
  end

  # because phar is open to exploitation if not readonly
  # this should always be set as a failsafe even though we totally disable phar ext
  describe php_config('phar.readonly') do
    its(:value) { should eq 1 }
  end

  describe php_config('log_errors') do
    its(:value) { should eq 1 }
  end

  describe php_config('error_log') do
    its(:value) { should eq '/var/log/php/error.log' }
  end

  # another security measure - never allow include from url
  describe php_config('allow_url_include') do
    its(:value) { should be_empty }
  end

  describe command('phpfpminfo --pool dp_default') do
    its(:stdout) { should contain "listen = /run/php_fpm_dp_default.sock" }
    its(:stdout) { should match /php_admin_value\[display_errors\] =\s*$/ }
    its(:stdout) { should contain "pm = ondemand" }
    its(:stdout) { should contain "pm.max_children = 20" }
    its(:stdout) { should contain "request_terminate_timeout = 60s" }
    its(:stdout) { should contain "request_terminate_timeout_track_finished = yes" }
    its(:stdout) { should contain "clear_env = no" }
  end

  describe command('phpfpminfo --pool dp_internal') do
    its(:stdout) { should contain "listen = /run/php_fpm_dp_internal.sock" }
    its(:stdout) { should match /php_admin_value\[display_errors\] =\s*$/ }
    its(:stdout) { should contain "pm = ondemand" }
    its(:stdout) { should contain "pm.max_children = 1000" }
    its(:stdout) { should contain "request_terminate_timeout = 60s" }
    its(:stdout) { should contain "request_terminate_timeout_track_finished = yes" }
    its(:stdout) { should contain "clear_env = no" }
  end

  describe command('phpfpminfo --pool dp_gql') do
    its(:stdout) { should contain "listen = /run/php_fpm_dp_gql.sock" }
    its(:stdout) { should match /php_admin_value\[display_errors\] =\s*$/ }
    its(:stdout) { should contain "pm = ondemand" }
    its(:stdout) { should contain "pm.max_children = 20" }
    its(:stdout) { should contain "request_terminate_timeout = 60s" }
    its(:stdout) { should contain "request_terminate_timeout_track_finished = yes" }
    its(:stdout) { should contain "clear_env = no" }
  end

  describe command('phpfpminfo --pool dp_broadcaster') do
    its(:stdout) { should contain "listen = /run/php_fpm_dp_broadcaster.sock" }
    its(:stdout) { should match /php_admin_value\[display_errors\] =\s*$/ }
    its(:stdout) { should contain "pm = ondemand" }
    its(:stdout) { should contain "pm.max_children = 1000" }
    its(:stdout) { should contain "request_terminate_timeout = 65s" }
    its(:stdout) { should contain "request_terminate_timeout_track_finished = yes" }
    its(:stdout) { should contain "clear_env = no" }
  end
end
