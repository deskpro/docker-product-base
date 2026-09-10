require 'spec_helper'

# Container booted with only /deskpro/ssl/mysql/ca.pem mounted and
# DESKPRO_DB_SSL_VERIFY_SERVER_CERT=true.
#
# A CA-only mount used to be ignored entirely - the copy sat inside the client
# cert/key guard - so this is the case the whole change exists for.
describe "MySQL TLS: CA cert only, with server cert verification" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe file('/srv/deskpro/INSTANCE_DATA/mysql-ca.pem') do
    it { should be_file }
    it { should be_owned_by 'root' }
    it { should be_grouped_into 'root' }
    it { should be_mode 644 }
  end

  describe file('/srv/deskpro/INSTANCE_DATA/mysql-client.crt') do
    it { should_not exist }
  end

  describe file('/srv/deskpro/INSTANCE_DATA/mysql-client.key') do
    it { should_not exist }
  end

  it "enables TLS against the mounted CA with no client certificate" do
    config = File.read('/srv/deskpro/INSTANCE_DATA/deskpro-config.php')
    expect(config).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT] = true;"
    expect(config).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_CA] = '/srv/deskpro/INSTANCE_DATA/mysql-ca.pem';"
    expect(config).not_to include "MYSQL_ATTR_SSL_CERT"
    expect(config).not_to include "MYSQL_ATTR_SSL_KEY"
  end

  # The CA belongs to the database connection only - it must not be pushed into
  # the OS trust store, where it would widen trust for every other TLS client.
  describe file('/usr/local/share/ca-certificates/deskpro-mysql-ca.pem') do
    it { should_not exist }
  end

  describe file('/usr/local/share/ca-certificates/deskpro-mysql-ca.crt') do
    it { should_not exist }
  end
end
