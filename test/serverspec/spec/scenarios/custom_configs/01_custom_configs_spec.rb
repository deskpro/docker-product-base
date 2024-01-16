require 'spec_helper'

describe "Ensure custom config files work as expected" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe file('/etc/php/8.1/fpm/conf.d/99-custom.ini') do
    it { should exist }
  end

  describe file('/etc/php/8.1/fpm/conf.d/99-custom_tmpl.ini') do
    it { should exist }
  end

  describe file('/etc/php/8.1/fpm/conf.d/99-custom_tmpl.ini.tmpl') do
    it { should exist }
  end

  it "phpinfo should have the overridden configs" do
    output = `php -r "echo ini_get('memory_limit').PHP_EOL; echo ini_get('date.timezone');"`
    exit_code = $?.exitstatus
    expect(exit_code).to eq 0
    expect(output).to include("1000008891")
    expect(output).to include("Arctic/Longyearbyen")
  end
end
