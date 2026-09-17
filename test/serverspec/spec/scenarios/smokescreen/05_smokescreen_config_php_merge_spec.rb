require 'spec_helper'

# Container runs with a stub dump-cfg emitting the full documented shape.
describe "NO_PROXY merges hosts read from dump-cfg (config.php)" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  it "includes every configured host, reduced to bare hostnames" do
    content = File.read('/etc/supervisor/conf.d/web.conf')
    php_fpm_block = content.split('[program:').find { |b| b.start_with?('php_fpm]') }
    no_proxy_value = php_fpm_block[/NO_PROXY="([^"]*)"/, 1]

    %w[
      db-primary.internal db-read.internal db-reports.internal
      apiv2.internal apiv1.internal channels.internal blobs.internal
      es-cfg.internal tika-cfg.internal
      redis-cfg.internal redis-url-cfg.internal
      otel-cfg.internal
    ].each do |host|
      expect(no_proxy_value).to include(host)
    end

    # Scheme/port/credentials must not leak through into NO_PROXY itself.
    expect(no_proxy_value).not_to include 'http://'
    expect(no_proxy_value).not_to include ':8080'
    expect(no_proxy_value).not_to include ':9998'
    expect(no_proxy_value).not_to include ':6379'
    expect(no_proxy_value).not_to include ':4318'
  end
end
