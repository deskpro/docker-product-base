require 'spec_helper'

# Container is run with DESKPRO_DB_HOST set and NO_PROXY set to an extra
# operator host (see Earthfile test-smokescreen target). Other internal
# backend host vars (DESKPRO_DB_READ_HOST, DESKPRO_DB_REPORTS_HOST,
# DESKPRO_REDIS_HOST, DESKPRO_ES_URL, DESKPRO_ES_TIKA_HOST) are left unset.
describe "NO_PROXY default is derived and additive" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  it "includes the set backend host, no empties for unset ones, and appends the operator entry" do
    content = File.read('/etc/supervisor/conf.d/web.conf')
    php_fpm_block = content.split('[program:').find { |b| b.start_with?('php_fpm]') }

    expect(php_fpm_block).to include 'NO_PROXY="localhost,127.0.0.1,::1,host.docker.internal,dbhost.internal,operator-extra.internal"'
    # No doubled/empty commas from the unset backend vars.
    expect(php_fpm_block).not_to include ',,'
  end
end
