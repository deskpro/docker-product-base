require 'spec_helper'

# The mysql-primary, mysql-read and mysqldump-primary helper CLIs re-render
# user.my.cnf.tmpl into ~/.my-auto.cnf on every invocation, then hand it to the
# mysql client with --defaults-group-suffix. They have to reach the server the
# same way PDO does, so the TLS inputs are resolved exactly as they are in
# deskpro-config.php.tmpl - see mysql-tls-config_spec.rb for that side.
describe "MySQL TLS: ssl options in the mysql helper CLI config" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  before(:each) do
    clear_mysql_certs
    clear_mysql_env
  end

  after(:all) do
    clear_mysql_certs
    clear_mysql_env
  end

  def render_cnf
    `eval-tpl -f /usr/local/share/deskpro/templates/user.my.cnf.tmpl`
  end

  # Returns just the body of one [group] out of the rendered cnf, so an
  # assertion about client_read cannot accidentally pass on client_primary.
  def group(cnf, name)
    cnf[/^\[#{Regexp.escape(name)}\]\n(.*?)(?=\n\[|\z)/m, 1].to_s
  end

  def mysql_cert_paths
    %w[mysql mysql-read mysql-reports]
      .product(%w[client.crt client.key ca.pem])
      .map { |prefix, suffix| "/srv/deskpro/INSTANCE_DATA/#{prefix}-#{suffix}" }
  end

  def install_mysql_certs(*names)
    names.each do |name|
      File.write("/srv/deskpro/INSTANCE_DATA/#{name}", "test fixture\n")
    end
  end

  def clear_mysql_certs
    mysql_cert_paths.each { |path| File.delete(path) if File.exist?(path) }
  end

  def clear_mysql_env
    %w[DESKPRO_DB DESKPRO_DB_READ DESKPRO_DB_REPORTS].each do |prefix|
      ENV.delete("#{prefix}_SSL_ENABLED")
      ENV.delete("#{prefix}_SSL_VERIFY_SERVER_CERT")
    end
    ENV.delete('DESKPRO_DB_READ_HOST')
  end

  context "with no certs and no env vars" do
    it "emits no ssl options, leaving the client at its own default" do
      expect(render_cnf).not_to include "ssl-"
    end
  end

  context "with DESKPRO_DB_SSL_ENABLED=true" do
    it "requires encryption on every group, with no CA of any kind" do
      ENV['DESKPRO_DB_SSL_ENABLED'] = 'true'
      cnf = render_cnf
      %w[client_primary client_read client_mysqldump].each do |name|
        section = group(cnf, name)
        expect(section).to include 'ssl-mode=REQUIRED'
        # there is no ssl-capath fallback - 20-certs.sh refuses to boot rather
        # than let verification run without a real CA file
        expect(section).not_to include 'ssl-ca'
      end
    end

    # VERIFY_IDENTITY is the client-side equivalent of mysqlnd's
    # MYSQL_ATTR_SSL_VERIFY_SERVER_CERT: chain plus hostname.
    it "verifies the server when DESKPRO_DB_SSL_VERIFY_SERVER_CERT=true" do
      install_mysql_certs('mysql-ca.pem')
      ENV['DESKPRO_DB_SSL_VERIFY_SERVER_CERT'] = 'true'
      section = group(render_cnf, 'client_primary')
      expect(section).to include 'ssl-mode=VERIFY_IDENTITY'
      expect(section).to include 'ssl-ca="/srv/deskpro/INSTANCE_DATA/mysql-ca.pem"'
    end
  end

  context "with a CA and a client certificate installed" do
    it "points every group at them" do
      install_mysql_certs('mysql-ca.pem', 'mysql-client.crt', 'mysql-client.key')
      cnf = render_cnf
      %w[client_primary client_read client_mysqldump].each do |name|
        section = group(cnf, name)
        expect(section).to include 'ssl-ca="/srv/deskpro/INSTANCE_DATA/mysql-ca.pem"'
        expect(section).to include 'ssl-cert="/srv/deskpro/INSTANCE_DATA/mysql-client.crt"'
        expect(section).to include 'ssl-key="/srv/deskpro/INSTANCE_DATA/mysql-client.key"'
      end
    end
  end

  context "with a separate read connection" do
    before(:each) { ENV['DESKPRO_DB_READ_HOST'] = 'mysql-read' }

    it "gives mysql-read its own CA and leaves the primary alone" do
      install_mysql_certs('mysql-ca.pem', 'mysql-read-ca.pem')
      cnf = render_cnf
      expect(group(cnf, 'client_read')).to include 'ssl-ca="/srv/deskpro/INSTANCE_DATA/mysql-read-ca.pem"'
      expect(group(cnf, 'client_primary')).to include 'ssl-ca="/srv/deskpro/INSTANCE_DATA/mysql-ca.pem"'
      expect(group(cnf, 'client_mysqldump')).to include 'ssl-ca="/srv/deskpro/INSTANCE_DATA/mysql-ca.pem"'
    end

    # directory scoping again: read supplied a cert, so it takes none of the
    # primary's client identity
    it "does not lend the primary's client certificate to a self-describing read" do
      install_mysql_certs('mysql-ca.pem', 'mysql-client.crt', 'mysql-client.key',
                          'mysql-read-ca.pem')
      section = group(render_cnf, 'client_read')
      expect(section).to include 'ssl-ca="/srv/deskpro/INSTANCE_DATA/mysql-read-ca.pem"'
      expect(section).not_to include 'ssl-cert'
      expect(section).not_to include 'ssl-key'
    end

    it "honours an explicit false on the read connection" do
      ENV['DESKPRO_DB_SSL_ENABLED'] = 'true'
      ENV['DESKPRO_DB_READ_SSL_ENABLED'] = 'false'
      cnf = render_cnf
      expect(group(cnf, 'client_read')).not_to include 'ssl-mode'
      expect(group(cnf, 'client_primary')).to include 'ssl-mode=REQUIRED'
    end

    it "falls the read group back to the primary's settings" do
      install_mysql_certs('mysql-ca.pem')
      expect(group(render_cnf, 'client_read')).to include 'ssl-ca="/srv/deskpro/INSTANCE_DATA/mysql-ca.pem"'
    end

    it "takes verification per connection" do
      install_mysql_certs('mysql-ca.pem')
      ENV['DESKPRO_DB_READ_SSL_VERIFY_SERVER_CERT'] = 'true'
      cnf = render_cnf
      expect(group(cnf, 'client_read')).to include 'ssl-mode=VERIFY_IDENTITY'
      expect(group(cnf, 'client_primary')).to include 'ssl-mode=REQUIRED'
    end
  end

  # End to end: the CLI itself must write the options out, not just the
  # template. The connection attempt fails (there is no database in this
  # image) - what matters is the file it leaves behind.
  context "running a helper CLI" do
    it "writes the ssl options into ~/.my-auto.cnf" do
      install_mysql_certs('mysql-ca.pem')
      cnf_path = File.join(ENV.fetch('HOME'), '.my-auto.cnf')
      File.delete(cnf_path) if File.exist?(cnf_path)

      system('mysql-primary -e "SELECT 1" >/dev/null 2>&1')

      expect(File.exist?(cnf_path)).to be true
      expect(group(File.read(cnf_path), 'client_primary'))
        .to include 'ssl-ca="/srv/deskpro/INSTANCE_DATA/mysql-ca.pem"'
    end
  end
end
