require 'spec_helper'
require 'json'

# Container booted with /deskpro/ssl/mysql/{ca.pem,client.crt,client.key} mounted
# and no DESKPRO_DB_SSL_* env vars set.
describe "MySQL TLS: client certificate and custom CA mounted" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe file('/srv/deskpro/INSTANCE_DATA/mysql-ca.pem') do
    it { should be_file }
    it { should be_owned_by 'root' }
    it { should be_grouped_into 'root' }
    # the CA is public, and PHP-FPM runs as dp_app so it has to be readable
    it { should be_mode 644 }
  end

  describe file('/srv/deskpro/INSTANCE_DATA/mysql-client.crt') do
    it { should be_file }
  end

  describe file('/srv/deskpro/INSTANCE_DATA/mysql-client.key') do
    it { should be_file }
  end

  it "points PDO at the mounted CA and the client certificate" do
    config = File.read('/srv/deskpro/INSTANCE_DATA/deskpro-config.php')
    expect(config).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT] = false;"
    expect(config).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_CA] = '/srv/deskpro/INSTANCE_DATA/mysql-ca.pem';"
    expect(config).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_CERT] = \"/srv/deskpro/INSTANCE_DATA/mysql-client.crt\";"
    expect(config).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_KEY] = \"/srv/deskpro/INSTANCE_DATA/mysql-client.key\";"
  end

  it "attaches the SSL options to the database config PHP actually loads" do
    script = <<~PHP
      require "/srv/deskpro/INSTANCE_DATA/config.php";
      $opts = $CONFIG["database"]["pdo_options"];
      echo json_encode([
        "verify" => $opts[PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT],
        "ca"     => $opts[PDO::MYSQL_ATTR_SSL_CA],
        "cert"   => $opts[PDO::MYSQL_ATTR_SSL_CERT],
        "key"    => $opts[PDO::MYSQL_ATTR_SSL_KEY],
      ]);
    PHP

    output = IO.popen(['php', '-r', script], &:read)
    expect($?.exitstatus).to eq 0

    parsed = JSON.parse(output)
    expect(parsed['verify']).to eq false
    expect(parsed['ca']).to eq '/srv/deskpro/INSTANCE_DATA/mysql-ca.pem'
    expect(parsed['cert']).to eq '/srv/deskpro/INSTANCE_DATA/mysql-client.crt'
    expect(parsed['key']).to eq '/srv/deskpro/INSTANCE_DATA/mysql-client.key'
  end
end
