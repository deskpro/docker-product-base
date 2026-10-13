require 'spec_helper'
require 'socket'
require 'timeout'

# Container is run with DISABLE_DESKPRO_PROXY_SERVICE=false plus pre-set
# proxy vars (see Earthfile test-smokescreen target):
#   HTTP_PROXY=http://192.168.90.2:3128   (wins over the differing lowercase)
#   http_proxy=http://10.0.0.9:3128
#   ALL_PROXY=http://u:p%40ss@127.0.0.1:8888  (fills the empty HTTPS upstream;
#                                          password is "p@ss")
describe "smokescreen picks up pre-set *_PROXY vars as its upstream" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  conf_path = '/etc/supervisor/conf.d/smokescreen.conf'

  describe process('smokescreen') do
    it { should be_running }
    # The upstream URL may carry credentials: env only, never argv.
    its(:args) { should_not include 'http://' }
  end

  describe file(conf_path) do
    it { should be_mode 600 }
    its(:content) { should include %(SMOKESCREEN_UPSTREAM_HTTP_PROXY="http://192.168.90.2:3128") }
    # %% is supervisor's escape for a literal %.
    its(:content) { should include %(SMOKESCREEN_UPSTREAM_HTTPS_PROXY="http://u:p%%40ss@127.0.0.1:8888") }
    its(:content) { should_not include '10.0.0.9' }
  end

  it "keeps the upstream out of supervisord's (and so the app's) environment" do
    environ = File.read("/proc/#{File.read('/run/supervisord.pid').strip}/environ")
    expect(environ).not_to include 'SMOKESCREEN_UPSTREAM_'
    expect(environ).not_to include '192.168.90.2'
    expect(environ).not_to include 'p%40ss'
  end

  %w[web tasks email messenger].each do |n|
    describe file("/etc/supervisor/conf.d/#{n}.conf") do
      its(:content) { should include 'HTTP_PROXY="http://127.0.0.1:3128"' }
      its(:content) { should include 'HTTPS_PROXY="http://127.0.0.1:3128"' }
      its(:content) { should_not include '192.168.90.2' }
    end
  end

  describe file('/var/log/docker-boot.log') do
    its(:content) { should match(/"lvl":"WARNING".*HTTP_PROXY and http_proxy are both set but differ/) }
  end

  describe file('/var/log/supervisor/smokescreen.log') do
    # main.go's "upstream proxy configured" line (logrus JSON, keys sorted).
    its(:content) { should match(/"allow_addresses":[^\n]*"192\.168\.90\.2:3128"/) }
    # Only scheme://host:port is logged, never the userinfo.
    its(:content) { should_not include 'p%40ss' }
  end

  # End to end: a CONNECT through smokescreen to a public IP should be
  # forwarded to the HTTPS upstream (127.0.0.1:8888, a stand-in listener
  # here). Reaching it at all proves both the upstream wiring and the
  # allow-list entry (loopback is otherwise blocked by smokescreen). The
  # Proxy-Authorization must carry the decoded password ("u:p@ss"), not
  # goproxy's percent-encoded form.
  it "forwards CONNECT requests to the upstream proxy" do
    server = TCPServer.new('127.0.0.1', 8888)
    received = []
    listener = Thread.new do
      Timeout.timeout(10) do
        client = server.accept
        while (line = client.gets) && line != "\r\n"
          received << line
        end
        client.write("HTTP/1.1 502 Bad Gateway\r\n\r\n")
        client.close
      end
    rescue Timeout::Error
      nil
    end

    `curl -s -o /dev/null -x http://127.0.0.1:3128 --max-time 8 https://1.1.1.1/ 2>/dev/null`
    listener.join
    server.close

    expect(received.first).to start_with('CONNECT 1.1.1.1:443')
    expect(received).to include("Proxy-Authorization: Basic #{['u:p@ss'].pack('m0')}\r\n")
  end
end
