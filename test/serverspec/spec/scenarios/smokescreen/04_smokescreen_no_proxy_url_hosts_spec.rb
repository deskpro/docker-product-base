require 'spec_helper'

# Container is run with DESKPRO_ES_URL, DESKPRO_ES_TIKA_HOST, DESKPRO_REDIS_URL,
# and OTEL_EXPORTER_OTLP_ENDPOINT all set to full URLs (see Earthfile
# test-smokescreen target) -- all URL-shaped despite some being named "_HOST".
# Guards against a silent regression in extract_host's URL parsing
# (scheme/credentials/port/path stripping).
describe "NO_PROXY derivation strips scheme/port/path from URL-shaped backend vars" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  it "includes the bare hosts and excludes the scheme/port" do
    content = File.read('/etc/supervisor/conf.d/web.conf')
    php_fpm_block = content.split('[program:').find { |b| b.start_with?('php_fpm]') }

    expect(php_fpm_block).to include 'NO_PROXY="localhost,127.0.0.1,::1,host.docker.internal,es.internal,tika.internal,redis.internal,otel-collector.internal"'
    expect(php_fpm_block).not_to include 'es.internal:9200'
    expect(php_fpm_block).not_to include 'https://'
    expect(php_fpm_block).not_to include 'tika.internal:9998'
    expect(php_fpm_block).not_to include 'redis.internal:6379'
    expect(php_fpm_block).not_to include 'otel-collector.internal:4318'
  end
end
