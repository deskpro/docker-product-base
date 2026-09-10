require 'spec_helper'

# Container booted with DESKPRO_DB_SSL_ENABLED=true and nothing mounted under
# /deskpro/ssl/mysql/. This is the MySQL "REQUIRE SSL" case: encryption with no
# certificates of any kind.
#
# Going through a real boot also proves the var survives 10-container-config.sh
# moving it to /run/container-config and swapping the env to a _FILE pointer.
describe "MySQL TLS: DESKPRO_DB_SSL_ENABLED with no certificates" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe file('/srv/deskpro/INSTANCE_DATA/mysql-ca.pem') do
    it { should_not exist }
  end

  describe file('/srv/deskpro/INSTANCE_DATA/mysql-client.crt') do
    it { should_not exist }
  end

  describe file('/srv/deskpro/INSTANCE_DATA/mysql-client.key') do
    it { should_not exist }
  end

  it "enables TLS against the system CA path" do
    config = File.read('/srv/deskpro/INSTANCE_DATA/deskpro-config.php')
    expect(config).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT] = false;"
    expect(config).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_CA] = '/etc/ssl/certs';"
    expect(config).not_to include "MYSQL_ATTR_SSL_CERT"
    expect(config).not_to include "MYSQL_ATTR_SSL_KEY"
  end

  it "is registered as a public container var" do
    expect(File.read('/usr/local/share/deskpro/container-public-var-list'))
      .to include "DESKPRO_DB_SSL_ENABLED\n"
    expect(File.read('/usr/local/share/deskpro/container-public-var-list'))
      .to include "DESKPRO_DB_SSL_VERIFY_SERVER_CERT\n"
  end
end
