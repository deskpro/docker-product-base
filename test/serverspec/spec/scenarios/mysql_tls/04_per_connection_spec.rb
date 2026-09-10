require 'spec_helper'
require 'json'

# Container booted with a different set of certificates per connection:
#
#   /deskpro/ssl/mysql/          client pair + CA   -> primary
#   /deskpro/ssl/mysql/read/     CA only            -> read
#   /deskpro/ssl/mysql/reports/  client pair + CA   -> reports
#
# plus DESKPRO_DB_READ_HOST / DESKPRO_DB_REPORTS_HOST so the extra connections
# are rendered at all, and DESKPRO_DB_REPORTS_SSL_VERIFY_SERVER_CERT=true to
# prove verification is settable per connection.
#
# The read mount deliberately holds a CA and nothing else. Certificates are
# directory-scoped, so that makes read self-describing: it uses its own CA and
# must NOT pick up the primary's client certificate.
describe "MySQL TLS: separate certificates per connection" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  %w[
    mysql-ca.pem mysql-client.crt mysql-client.key
    mysql-read-ca.pem
    mysql-reports-ca.pem mysql-reports-client.crt mysql-reports-client.key
  ].each do |name|
    describe file("/srv/deskpro/INSTANCE_DATA/#{name}") do
      it { should be_file }
    end
  end

  # the read mount has no client pair, so nothing should have been installed
  describe file('/srv/deskpro/INSTANCE_DATA/mysql-read-client.crt') do
    it { should_not exist }
  end

  describe file('/srv/deskpro/INSTANCE_DATA/mysql-read-ca.pem') do
    it { should be_owned_by 'root' }
    it { should be_mode 644 }
  end

  describe file('/srv/deskpro/INSTANCE_DATA/mysql-reports-ca.pem') do
    it { should be_owned_by 'root' }
    it { should be_mode 644 }
  end

  context "the rendered config" do
    let(:config) { File.read('/srv/deskpro/INSTANCE_DATA/deskpro-config.php') }

    it "gives each connection its own options array" do
      expect(config).to include "$pdo_options_read = [];"
      expect(config).to include "$pdo_options_reports = [];"
      expect(config).to include "'pdo_options' => $pdo_options ?? [],"
      expect(config).to include "'pdo_options' => $pdo_options_read ?? [],"
      expect(config).to include "'pdo_options' => $pdo_options_reports ?? [],"
    end

    it "uses the primary certificates for the primary connection" do
      expect(config).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_CA] = '/srv/deskpro/INSTANCE_DATA/mysql-ca.pem';"
      expect(config).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_CERT] = \"/srv/deskpro/INSTANCE_DATA/mysql-client.crt\";"
      expect(config).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT] = false;"
    end

    it "gives read its own CA and none of the primary's client identity" do
      expect(config).to include "$pdo_options_read[\\PDO::MYSQL_ATTR_SSL_CA] = '/srv/deskpro/INSTANCE_DATA/mysql-read-ca.pem';"
      expect(config).not_to include "$pdo_options_read[\\PDO::MYSQL_ATTR_SSL_CERT]"
      expect(config).not_to include "$pdo_options_read[\\PDO::MYSQL_ATTR_SSL_KEY]"
      expect(config).to include "$pdo_options_read[\\PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT] = false;"
    end

    it "gives reports its own CA, client certificate and verification setting" do
      expect(config).to include "$pdo_options_reports[\\PDO::MYSQL_ATTR_SSL_CA] = '/srv/deskpro/INSTANCE_DATA/mysql-reports-ca.pem';"
      expect(config).to include "$pdo_options_reports[\\PDO::MYSQL_ATTR_SSL_CERT] = \"/srv/deskpro/INSTANCE_DATA/mysql-reports-client.crt\";"
      expect(config).to include "$pdo_options_reports[\\PDO::MYSQL_ATTR_SSL_KEY] = \"/srv/deskpro/INSTANCE_DATA/mysql-reports-client.key\";"
      expect(config).to include "$pdo_options_reports[\\PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT] = true;"
    end
  end

  it "attaches the right options to each connection PHP actually loads" do
    script = <<~PHP
      require "/srv/deskpro/INSTANCE_DATA/config.php";
      $out = [];
      foreach ([
        "primary" => $CONFIG["database"],
        "read"    => $CONFIG["database_advanced"]["read"],
        "reports" => $CONFIG["database_advanced"]["read_reports"],
      ] as $name => $conn) {
        $opts = $conn["pdo_options"];
        $out[$name] = [
          "verify" => $opts[PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT],
          "ca"     => $opts[PDO::MYSQL_ATTR_SSL_CA],
          "cert"   => $opts[PDO::MYSQL_ATTR_SSL_CERT] ?? null,
        ];
      }
      echo json_encode($out);
    PHP

    output = IO.popen(['php', '-r', script], &:read)
    expect($?.exitstatus).to eq 0

    parsed = JSON.parse(output)
    expect(parsed['primary']['ca']).to eq '/srv/deskpro/INSTANCE_DATA/mysql-ca.pem'
    expect(parsed['primary']['cert']).to eq '/srv/deskpro/INSTANCE_DATA/mysql-client.crt'
    expect(parsed['primary']['verify']).to eq false

    expect(parsed['read']['ca']).to eq '/srv/deskpro/INSTANCE_DATA/mysql-read-ca.pem'
    expect(parsed['read']['cert']).to be_nil
    expect(parsed['read']['verify']).to eq false

    expect(parsed['reports']['ca']).to eq '/srv/deskpro/INSTANCE_DATA/mysql-reports-ca.pem'
    expect(parsed['reports']['cert']).to eq '/srv/deskpro/INSTANCE_DATA/mysql-reports-client.crt'
    expect(parsed['reports']['verify']).to eq true
  end

  # The helper CLIs read ~/.my-auto.cnf, which each of them re-renders from
  # user.my.cnf.tmpl on every invocation. Render it the same way here.
  context "the mysql helper CLI config" do
    let(:cnf) do
      `eval-tpl -f /usr/local/share/deskpro/templates/user.my.cnf.tmpl`
    end

    def group(cnf, name)
      cnf[/^\[#{Regexp.escape(name)}\]\n(.*?)(?=\n\[|\z)/m, 1].to_s
    end

    it "gives mysql-primary and mysqldump-primary the primary certificates" do
      %w[client_primary client_mysqldump].each do |name|
        section = group(cnf, name)
        expect(section).to include 'ssl-mode=REQUIRED'
        expect(section).to include 'ssl-ca="/srv/deskpro/INSTANCE_DATA/mysql-ca.pem"'
        expect(section).to include 'ssl-cert="/srv/deskpro/INSTANCE_DATA/mysql-client.crt"'
        expect(section).to include 'ssl-key="/srv/deskpro/INSTANCE_DATA/mysql-client.key"'
      end
    end

    it "gives mysql-read the read CA and no client certificate" do
      section = group(cnf, 'client_read')
      expect(section).to include 'ssl-mode=REQUIRED'
      expect(section).to include 'ssl-ca="/srv/deskpro/INSTANCE_DATA/mysql-read-ca.pem"'
      expect(section).not_to include 'ssl-cert'
    end
  end
end
