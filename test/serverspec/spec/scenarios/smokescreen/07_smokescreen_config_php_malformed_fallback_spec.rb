require 'spec_helper'

# Container runs with a stub dump-cfg that exits 0 but emits non-JSON stdout.
describe "NO_PROXY falls back cleanly when dump-cfg emits non-JSON stdout" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  it "still boots and derives NO_PROXY from env vars alone" do
    content = File.read('/etc/supervisor/conf.d/web.conf')
    php_fpm_block = content.split('[program:').find { |b| b.start_with?('php_fpm]') }

    expect(php_fpm_block).to include 'NO_PROXY="localhost,127.0.0.1,::1,host.docker.internal,dbhost.internal"'
  end
end
