require 'spec_helper'

# Container runs with a stub dump-cfg that omits services/api/internalHosts
# (the shape emitted before those keys existed).
describe "NO_PROXY tolerates dump-cfg output missing the newer keys" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  it "doesn't crash and still extracts the hosts that are present" do
    content = File.read('/etc/supervisor/conf.d/web.conf')
    php_fpm_block = content.split('[program:').find { |b| b.start_with?('php_fpm]') }
    no_proxy_value = php_fpm_block[/NO_PROXY="([^"]*)"/, 1]

    expect(no_proxy_value).to include('db-primary.internal')
    expect(no_proxy_value).to include('es-cfg.internal')
    expect(no_proxy_value).to include('redis-cfg.internal')
  end
end
