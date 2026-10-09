require 'spec_helper'

# Container is run in web mode with the PHP_OPCACHE_* sizing env vars set
# (see Earthfile test-opcache-override target): the rendered php ini must
# reflect the overrides rather than the defaults.
describe "opcache sizing: env overrides are applied to the rendered ini" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe file('/etc/php/8.3/mods-available/deskpro.ini') do
    its(:content) { should match /^opcache\.max_accelerated_files = "?12345"?$/ }
    its(:content) { should match /^opcache\.memory_consumption = "?256"?$/ }
    its(:content) { should match /^opcache\.interned_strings_buffer = "?48"?$/ }
  end

  describe php_config('opcache.max_accelerated_files') do
    its(:value) { should eq 12345 }
  end

  describe php_config('opcache.memory_consumption') do
    its(:value) { should eq 256 }
  end

  describe php_config('opcache.interned_strings_buffer') do
    its(:value) { should eq 48 }
  end
end
