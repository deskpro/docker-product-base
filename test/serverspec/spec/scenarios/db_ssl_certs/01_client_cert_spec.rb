require 'spec_helper'

CA_PATH = '/srv/deskpro/INSTANCE_DATA/mysql-ca.crt'.freeze

# Scenario: /deskpro/ssl/mysql/ is mounted with a CA *and* a client cert pair,
# i.e. a server that requires X509 client authentication.
describe "DB SSL certs: client cert pair mounted alongside a CA" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  # Regression: a CA-only mount used to be ignored, and the CA was copied with
  # a *.pem name into the trust-store input dir where it did nothing.
  describe file(CA_PATH) do
    it { should exist }
    it { should be_owned_by 'root' }
    it { should be_grouped_into 'root' }
    it { should be_mode 644 }
  end

  it "does not add the MySQL CA to the system trust bundle" do
    body = File.read('/deskpro/ssl/mysql/ca.pem')
                .lines
                .reject { |l| l.start_with?('-----') }
                .map(&:strip)
                .reject(&:empty?)
    bundle = File.read('/etc/ssl/certs/ca-certificates.crt')
    expect(bundle).not_to include(body[1])
  end

  it "installs the CA as a parseable PEM - the mysql client reads it" do
    expect(`openssl x509 -in #{CA_PATH} -noout -subject 2>&1`).to include('CN')
    expect($?.exitstatus).to eq 0
  end

  describe file('/srv/deskpro/INSTANCE_DATA/mysql-client.crt') do
    it { should exist }
    it { should be_mode 644 }
  end

  # The private key must not be world readable, but php-fpm runs as dp_app.
  describe file('/srv/deskpro/INSTANCE_DATA/mysql-client.key') do
    it { should exist }
    it { should be_owned_by 'root' }
    it { should be_grouped_into 'dp_app' }
    it { should be_mode 640 }
  end

  it "encrypts the connection and sends the client cert" do
    output = `eval-tpl -f /usr/local/share/deskpro/templates/deskpro-config.php.tmpl`
    expect(output).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT] = false;"
    expect(output).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_CA] = '#{CA_PATH}';"
    expect(output).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_CERT] = '/srv/deskpro/INSTANCE_DATA/mysql-client.crt';"
    expect(output).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_KEY] = '/srv/deskpro/INSTANCE_DATA/mysql-client.key';"
  end

  it "configures the CLI clients the same way" do
    output = `eval-tpl -f /usr/local/share/deskpro/templates/user.my.cnf.tmpl`
    expect(output).to include "ssl=1"
    expect(output).to include "ssl-verify-server-cert=0"
    expect(output).to include "ssl-ca=/srv/deskpro/INSTANCE_DATA/mysql-ca.crt"
    expect(output).to include "ssl-cert=/srv/deskpro/INSTANCE_DATA/mysql-client.crt"
    expect(output).to include "ssl-key=/srv/deskpro/INSTANCE_DATA/mysql-client.key"
  end
end
