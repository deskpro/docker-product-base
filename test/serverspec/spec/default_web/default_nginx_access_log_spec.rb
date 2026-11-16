require 'spec_helper'
require 'json'
require 'securerandom'
require 'shellwords'

describe "nginx access log API key fields" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  # nginx writes the access log line after the response is sent, so curl can return first.
  def access_log_line_for(headers)
    transaction_id = SecureRandom.hex(16)
    header_args = (headers + ["X-Log-Transaction-Id: #{transaction_id}"]).map { |h| "-H #{Shellwords.escape(h)}" }.join(' ')
    system("curl -s -o /dev/null --max-time 10 #{header_args} http://127.0.0.1/") or raise "curl failed"

    50.times do
      line = File.foreach('/var/log/nginx/access.log').find { |l| l.include?(transaction_id) }
      return line if line
      sleep 0.1
    end
    raise "no access log line for transaction #{transaction_id}"
  end

  master_key = SecureRandom.hex(20)

  [
    { name: 'v2 key',                headers: ['Authorization: key 12:s3cr3tcode'],   key_id: '12', mode: 'key',        secret: 's3cr3tcode' },
    { name: 'v2 key, comma',         headers: ['Authorization: key,34:s3cr3tcode'],   key_id: '34', mode: 'key',        secret: 's3cr3tcode' },
    { name: 'legacy key',            headers: ['X-DeskPRO-API-Key: 12:s3cr3tcode'],   key_id: '12', mode: '',           secret: 's3cr3tcode' },
    { name: 'v2 wins over legacy',   headers: ['Authorization: key 56:s3cr3tcode', 'X-DeskPRO-API-Key: 78:s3cr3tcode'], key_id: '56', mode: 'key', secret: 's3cr3tcode' },
    { name: 'master key',            headers: ["Authorization: key #{master_key}"],   key_id: '',   mode: 'master_key', secret: master_key },
    { name: 'token',                 headers: ['Authorization: token abc'],           key_id: '',   mode: 'token' },
    { name: 'internal',              headers: ['Authorization: internal abc'],        key_id: '',   mode: 'internal' },
    { name: 'workspace',             headers: ['Authorization: workspace abc'],       key_id: '',   mode: 'workspace' },
    { name: 'no key',                headers: [],                                     key_id: '',   mode: '' },
  ].each do |c|
    context c[:name] do
      before(:all) { @line = access_log_line_for(c[:headers]) }

      it "logs api_key_id #{c[:key_id].inspect} and api_auth_mode #{c[:mode].inspect}" do
        entry = JSON.parse(@line)
        expect(entry['api_key_id']).to eq c[:key_id]
        expect(entry['api_auth_mode']).to eq c[:mode]
      end

      if c[:secret]
        it 'does not log the secret' do
          expect(@line).not_to include c[:secret]
        end
      end
    end
  end
end
