require 'spec_helper'

describe package('nginx') do
  it { should be_installed }
end

describe package('php8.3-cli') do
  it { should be_installed }
end

describe package('php8.3-fpm') do
  it { should be_installed }
end

describe package('supervisor') do
  it { should be_installed }
end

describe command('php -v') do
  its(:stdout) { should contain('PHP 8.3.') }
end

describe command('gomplate -v') do
  its(:stdout) { should contain('gomplate version 5.') }
end

describe command('vector -V') do
  its(:stdout) { should contain('vector 0.51.') }
end

%w[
  bcmath
  ctype
  curl
  dom
  fileinfo
  gd
  iconv
  imap
  intl
  ldap
  mbstring
  mysqlnd
  protobuf
  redis
  soap
  sqlite3
  xml
  zip
  Zend\ OPcache
].each do |ext|
  describe command('php -m') do
    its(:stdout) { should match(/^#{Regexp.escape(ext)}$/) }
  end
end

# opentelemetry is opt-in (loaded via DESKPRO_ENABLE_OTEL).
# Assert the .so file is present in the image.
%w[
  opentelemetry.so
].each do |so|
  describe file("/usr/lib/php/20230831/#{so}") do
    it { should exist }
  end
end

# New Relic was removed from the base image -- assert it stays gone.
describe file('/usr/lib/php/20230831/newrelic.so') do
  it { should_not exist }
end

describe file('/usr/local/bin/newrelic-daemon') do
  it { should_not exist }
end
