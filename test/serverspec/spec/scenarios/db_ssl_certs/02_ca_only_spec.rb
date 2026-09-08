require 'spec_helper'

CA_PATH = '/srv/deskpro/INSTANCE_DATA/mysql-ca.crt'.freeze

# Scenario: /deskpro/ssl/mysql/ holds only a CA - the common case for a server
# configured with REQUIRE SSL rather than REQUIRE X509.
describe "DB SSL certs: CA mounted without a client cert" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  # Regression: this copy used to be nested inside the client-cert guard, so a
  # CA-only mount was ignored entirely and the connection stayed plaintext.
  describe file(CA_PATH) do
    it { should exist }
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
    it { should_not exist }
  end

  it "encrypts the connection without sending a client cert" do
    output = `eval-tpl -f /usr/local/share/deskpro/templates/deskpro-config.php.tmpl`
    expect(output).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_CA] = '#{CA_PATH}';"
    expect(output).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT] = false;"
    expect(output).not_to include "MYSQL_ATTR_SSL_CERT"
    expect(output).not_to include "MYSQL_ATTR_SSL_KEY"
  end

  it "configures the CLI clients the same way" do
    output = `eval-tpl -f /usr/local/share/deskpro/templates/user.my.cnf.tmpl`
    expect(output).to include "ssl=1"
    expect(output).to include "ssl-ca=/srv/deskpro/INSTANCE_DATA/mysql-ca.crt"
    expect(output).not_to include "ssl-cert="
  end
end
