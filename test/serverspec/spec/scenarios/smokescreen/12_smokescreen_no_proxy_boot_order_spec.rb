require 'spec_helper'

# Boot-level guard against the 35-http-proxy.sh boot-order bug: this
# container's stub dump-cfg only succeeds once /srv/deskpro/INSTANCE_DATA/
# config.php exists (modeling the real dump-cfg's dependency on it), and
# emits walk-only sentinel hosts nowhere else in build_no_proxy_default's
# defaults. Boots through the real entrypoint, assembled-config case (no
# mounted/overridden config.php) -- config.php is built by
# 41-deskpro-config.sh same as any real container.
#
# RED on the boot-order bug: config.php doesn't exist yet when NO_PROXY
# is derived and baked into web.conf, so the stub fails and the sentinel
# hosts never appear.
# GREEN with the fix: NO_PROXY is derived (and web.conf rendered) after
# config.php is assembled, so dump-cfg succeeds and the sentinels land.
describe "NO_PROXY reflects config.php-derived hosts in the assembled-config boot path" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  it "includes the walk-only sentinel hosts baked into the rendered web.conf" do
    content = File.read('/etc/supervisor/conf.d/web.conf')
    php_fpm_block = content.split('[program:').find { |b| b.start_with?('php_fpm]') }
    no_proxy_value = php_fpm_block[/NO_PROXY="([^"]*)"/, 1]

    %w[
      noproxy-wiring-probe.invalid
      api-wiring-probe.invalid
      services-wiring-probe.invalid
    ].each do |host|
      expect(no_proxy_value).to include(host)
    end
  end
end
