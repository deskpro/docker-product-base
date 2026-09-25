require 'spec_helper'

# Container is run with DESKPRO_ES_URL, DESKPRO_ES_TIKA_HOST, DESKPRO_REDIS_URL,
# OTEL_EXPORTER_OTLP_ENDPOINT, and DESKPRO_API_BASE_URL_PRIVATE all set to
# full URLs (see Earthfile test-smokescreen target) -- all URL-shaped
# despite some being named "_HOST".
# Guards against a silent regression in extract_host's URL parsing
# (scheme/credentials/port/path stripping).
describe "NO_PROXY derivation strips scheme/port/path from URL-shaped backend vars" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  it "includes the bare hosts and excludes the scheme/port" do
    content = File.read('/etc/supervisor/conf.d/web.conf')
    php_fpm_block = content.split('[program:').find { |b| b.start_with?('php_fpm]') }

    no_proxy_value = php_fpm_block[/NO_PROXY="([^"]*)"/, 1]

    %w[localhost 127.0.0.1 ::1 host.docker.internal es.internal tika.internal redis.internal otel-collector.internal deskpro_example_web].each do |host|
      expect(no_proxy_value).to include(host)
    end

    expect(no_proxy_value).not_to include 'es.internal:9200'
    expect(no_proxy_value).not_to include 'https://'
    expect(no_proxy_value).not_to include 'tika.internal:9998'
    expect(no_proxy_value).not_to include 'redis.internal:6379'
    expect(no_proxy_value).not_to include 'otel-collector.internal:4318'
    expect(no_proxy_value).not_to include 'deskpro_example_web:80'
  end
end
