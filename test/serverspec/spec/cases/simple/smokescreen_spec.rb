require 'spec_helper'

# Default (web mode, no overrides): smokescreen should be on, listening on
# loopback only, wired into php_fpm's environment, and actually enforcing
# its built-in range blocking.
describe "smokescreen egress proxy: on by default" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe process('smokescreen') do
    it { should be_running }
  end

  describe file('/etc/supervisor/conf.d/smokescreen.conf') do
    its(:content) { should include "autostart=true" }
    its(:content) { should include "--listen-ip=127.0.0.1" }
    its(:content) { should include "--listen-port=3128" }
    its(:content) { should include "user=smokescreen" }
    its(:content) { should include "group=smokescreen" }
    # No --config-file flag when SMOKESCREEN_CONFIG_FILE is unset.
    its(:content) { should_not include "--config-file" }
  end

  it "listens on loopback only, not on all interfaces" do
    output = `ss -tlnp 2>/dev/null || netstat -tln 2>/dev/null`
    expect(output).to include "127.0.0.1:3128"
    expect(output).not_to include "0.0.0.0:3128"
  end

  it "embeds the default proxy vars into php_fpm's environment" do
    content = File.read('/etc/supervisor/conf.d/web.conf')
    php_fpm_block = content.split('[program:').find { |b| b.start_with?('php_fpm]') }
    expect(php_fpm_block).to include 'HTTP_PROXY="http://127.0.0.1:3128"'
    expect(php_fpm_block).to include 'HTTPS_PROXY="http://127.0.0.1:3128"'
    expect(php_fpm_block).to include 'NO_PROXY="localhost,127.0.0.1,::1,host.docker.internal"'
  end

  it "no-ops the config.php merge stub when dump-cfg isn't present (base image never ships it)" do
    expect(File.exist?('/srv/deskpro/serve/bin/dump-cfg')).to be false
  end

  describe "egress classification" do
    def proxied(url, timeout = 3)
      `curl -s -o /dev/null -D - -x http://127.0.0.1:3128 --max-time #{timeout} '#{url}' 2>/dev/null`
    end

    # Denied requests get a 407 with an X-Smokescreen-Error header (see
    # rejectResponse/denyError in pkg/smokescreen/smokescreen.go) -- not a
    # connection failure, so this doesn't depend on real network egress.
    it "denies the cloud metadata endpoint" do
      headers = proxied('http://169.254.169.254/')
      expect(headers).to match(/^HTTP\/[\d.]+ 407/)
      expect(headers).to include 'X-Smokescreen-Error'
    end

    it "denies an RFC1918 address" do
      headers = proxied('http://10.255.255.1/')
      expect(headers).to match(/^HTTP\/[\d.]+ 407/)
      expect(headers).to include 'X-Smokescreen-Error'
    end

    it "does not classify a public address as denied" do
      # Best-effort: a policy deny always comes back as 407 (see
      # rejectResponse/denyError). A dial failure also sets the
      # X-Smokescreen-Error header but as 502 -- that's an allowed
      # destination smokescreen simply couldn't reach (CI may have no real
      # egress), which is a different thing from a policy denial and is
      # what we're asserting against here.
      headers = proxied('http://1.1.1.1/', 5)
      expect(headers).not_to match(/^HTTP\/[\d.]+ 407/)
    end
  end
end
