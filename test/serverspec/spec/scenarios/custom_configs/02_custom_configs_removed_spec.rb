require 'spec_helper'

describe "Ensure custom config files work as expected" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe file('/etc/php/8.1/fpm/conf.d/99-custom.ini') do
    it { should_not exist }
  end

  describe file('/etc/php/8.1/fpm/conf.d/99-custom_tmpl.ini') do
    it { should_not exist }
  end

  describe file('/etc/php/8.1/fpm/conf.d/99-custom_tmpl.ini.tmpl') do
    it { should_not exist }
  end
end
