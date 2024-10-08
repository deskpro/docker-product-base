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
  its(:stdout) { should contain('gomplate version 3.') }
end

describe command('vector -V') do
  its(:stdout) { should contain('vector 0.39.') }
end
