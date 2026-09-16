require 'spec_helper'

# Container is run with DESKPRO_ES_URL and DESKPRO_ES_TIKA_HOST set to full
# URLs (see Earthfile test-smokescreen target) -- both of these vars are
# URLs despite one being named "_HOST". Guards against a silent regression
# in extract_host's URL parsing (scheme/credentials/port/path stripping).
describe "NO_PROXY derivation strips scheme/port/path from URL-shaped backend vars" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  it "includes the bare hosts and excludes the scheme/port" do
    content = File.read('/etc/supervisor/conf.d/web.conf')
    php_fpm_block = content.split('[program:').find { |b| b.start_with?('php_fpm]') }

    expect(php_fpm_block).to include 'NO_PROXY="localhost,127.0.0.1,::1,es.internal,tika.internal"'
    expect(php_fpm_block).not_to include 'es.internal:9200'
    expect(php_fpm_block).not_to include 'https://'
    expect(php_fpm_block).not_to include 'tika.internal:9998'
  end
end
