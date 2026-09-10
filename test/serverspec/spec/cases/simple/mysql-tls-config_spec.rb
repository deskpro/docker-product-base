require 'spec_helper'

# Renders deskpro-config.php.tmpl directly and checks the PDO SSL block for
# every combination of the two switches that drive it:
#
#   1. certs installed into INSTANCE_DATA (what 20-certs.sh copies out of
#      /deskpro/ssl/mysql/)
#   2. the DESKPRO_DB_SSL_* env vars
#
# 20-certs.sh itself - the mount handling and its hard failures - needs real
# mounts, so it lives in the mysql_tls scenario instead.
describe "MySQL TLS: PDO SSL options in deskpro-config.php" do
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

  # Note: use RSpec's literal `include` matcher, not serverspec's `contain`.
  # `contain` treats its argument as a regex, and the rendered PHP contains
  # metacharacters ($, [, ]) that would break matching.

  def render_config
    `eval-tpl -f /usr/local/share/deskpro/templates/deskpro-config.php.tmpl`
  end

  def mysql_cert_paths
    %w[mysql mysql-read mysql-reports]
      .product(%w[client.crt client.key ca.pem])
      .map { |prefix, suffix| "/srv/deskpro/INSTANCE_DATA/#{prefix}-#{suffix}" }
  end

  # Stands in for 20-certs.sh having copied the mounts into place. Nothing
  # reads the contents - the template only tests for existence.
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
    ENV.delete('DESKPRO_DB_REPORTS_HOST')
  end

  context "with no certs and no env vars" do
    it "emits no SSL options at all" do
      expect(render_config).not_to include "MYSQL_ATTR_SSL"
    end
  end

  context "with DESKPRO_DB_SSL_ENABLED=true and no certs" do
    it "enables TLS against the system CA path without a client certificate" do
      ENV['DESKPRO_DB_SSL_ENABLED'] = 'true'
      output = render_config
      expect(output).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT] = false;"
      expect(output).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_CA] = '/etc/ssl/certs';"
      expect(output).not_to include "MYSQL_ATTR_SSL_CERT"
      expect(output).not_to include "MYSQL_ATTR_SSL_KEY"
    end

    it "turns on server cert verification when DESKPRO_DB_SSL_VERIFY_SERVER_CERT=true" do
      ENV['DESKPRO_DB_SSL_ENABLED'] = 'true'
      ENV['DESKPRO_DB_SSL_VERIFY_SERVER_CERT'] = 'true'
      expect(render_config).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT] = true;"
    end
  end

  context "with DESKPRO_DB_SSL_ENABLED=false" do
    it "emits no SSL options" do
      ENV['DESKPRO_DB_SSL_ENABLED'] = 'false'
      expect(render_config).not_to include "MYSQL_ATTR_SSL"
    end
  end

  context "with only DESKPRO_DB_SSL_VERIFY_SERVER_CERT=true" do
    # Verification is a modifier, not a switch - on its own it must not turn
    # TLS on, or an operator could believe they are encrypted when they are not.
    it "does not enable TLS by itself" do
      ENV['DESKPRO_DB_SSL_VERIFY_SERVER_CERT'] = 'true'
      expect(render_config).not_to include "MYSQL_ATTR_SSL"
    end
  end

  context "with a CA cert installed and no client certificate" do
    it "enables TLS and points SSL_CA at the installed CA" do
      install_mysql_certs('mysql-ca.pem')
      output = render_config
      expect(output).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT] = false;"
      expect(output).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_CA] = '/srv/deskpro/INSTANCE_DATA/mysql-ca.pem';"
      expect(output).not_to include "MYSQL_ATTR_SSL_CERT"
      expect(output).not_to include "MYSQL_ATTR_SSL_KEY"
    end

    it "turns on server cert verification when DESKPRO_DB_SSL_VERIFY_SERVER_CERT=true" do
      install_mysql_certs('mysql-ca.pem')
      ENV['DESKPRO_DB_SSL_VERIFY_SERVER_CERT'] = 'true'
      output = render_config
      expect(output).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT] = true;"
      expect(output).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_CA] = '/srv/deskpro/INSTANCE_DATA/mysql-ca.pem';"
    end
  end

  context "with a client certificate and no CA cert" do
    # This is the pre-existing behaviour and the rendered output is deliberately
    # unchanged from before DESKPRO_DB_SSL_* existed. SSL_CA stays the
    # /etc/ssl/certs directory here even though MYSQL_ATTR_SSL_CA wants a file.
    it "renders the legacy client certificate block unchanged" do
      install_mysql_certs('mysql-client.crt', 'mysql-client.key')
      output = render_config
      expect(output).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT] = false;"
      expect(output).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_CA] = '/etc/ssl/certs';"
      expect(output).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_CERT] = \"/srv/deskpro/INSTANCE_DATA/mysql-client.crt\";"
      expect(output).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_KEY] = \"/srv/deskpro/INSTANCE_DATA/mysql-client.key\";"
    end
  end

  context "with a client certificate and a CA cert" do
    it "uses the installed CA alongside the client certificate" do
      install_mysql_certs('mysql-client.crt', 'mysql-client.key', 'mysql-ca.pem')
      output = render_config
      expect(output).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_CA] = '/srv/deskpro/INSTANCE_DATA/mysql-ca.pem';"
      expect(output).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_CERT] = \"/srv/deskpro/INSTANCE_DATA/mysql-client.crt\";"
      expect(output).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_KEY] = \"/srv/deskpro/INSTANCE_DATA/mysql-client.key\";"
    end
  end

  context "with half a client certificate pair" do
    # 20-certs.sh refuses to boot in this state, but the template must not
    # emit a half-configured client certificate if it ever sees one.
    it "emits no client certificate options" do
      install_mysql_certs('mysql-client.crt')
      output = render_config
      expect(output).not_to include "MYSQL_ATTR_SSL_CERT"
      expect(output).not_to include "MYSQL_ATTR_SSL_KEY"
    end

    it "does not enable TLS on its own" do
      install_mysql_certs('mysql-client.key')
      expect(render_config).not_to include "MYSQL_ATTR_SSL"
    end
  end

  # The read and read_reports connections can point at different servers behind
  # different CAs, so each gets its own $pdo_options_* array.
  #
  # Certificates are directory-scoped: any cert of its own makes a connection
  # self-describing and it inherits none of the primary's. The env vars cascade
  # the other way - unset takes the primary's value, explicit wins.
  context "with the read and reports connections configured" do
    before(:each) do
      ENV['DESKPRO_DB_READ_HOST'] = 'mysql-read'
      ENV['DESKPRO_DB_REPORTS_HOST'] = 'mysql-reports'
    end

    it "gives each connection its own options array, built from nothing" do
      output = render_config
      expect(output).to include "$pdo_options_read = [];"
      expect(output).to include "$pdo_options_reports = [];"
      expect(output).to include "'pdo_options' => $pdo_options ?? [],"
      expect(output).to include "'pdo_options' => $pdo_options_read ?? [],"
      expect(output).to include "'pdo_options' => $pdo_options_reports ?? [],"
    end

    it "inherits the primary's certificates when a connection supplies none" do
      install_mysql_certs('mysql-ca.pem', 'mysql-client.crt', 'mysql-client.key')
      output = render_config
      %w[$pdo_options $pdo_options_read $pdo_options_reports].each do |var|
        expect(output).to include "#{var}[\\PDO::MYSQL_ATTR_SSL_CA] = '/srv/deskpro/INSTANCE_DATA/mysql-ca.pem';"
        expect(output).to include "#{var}[\\PDO::MYSQL_ATTR_SSL_CERT] = \"/srv/deskpro/INSTANCE_DATA/mysql-client.crt\";"
      end
    end

    # The point of directory scoping: a CA in read/ must not silently drag the
    # primary's client certificate along with it.
    it "takes nothing from the primary once a connection supplies any cert" do
      install_mysql_certs('mysql-ca.pem', 'mysql-client.crt', 'mysql-client.key',
                          'mysql-read-ca.pem')
      output = render_config
      expect(output).to include "$pdo_options_read[\\PDO::MYSQL_ATTR_SSL_CA] = '/srv/deskpro/INSTANCE_DATA/mysql-read-ca.pem';"
      expect(output).not_to include "$pdo_options_read[\\PDO::MYSQL_ATTR_SSL_CERT]"
      expect(output).not_to include "$pdo_options_read[\\PDO::MYSQL_ATTR_SSL_KEY]"
      # the untouched connection still inherits everything
      expect(output).to include "$pdo_options_reports[\\PDO::MYSQL_ATTR_SSL_CERT] = \"/srv/deskpro/INSTANCE_DATA/mysql-client.crt\";"
    end

    it "uses only its own client certificate, not the primary's CA" do
      install_mysql_certs('mysql-ca.pem',
                          'mysql-reports-client.crt', 'mysql-reports-client.key')
      output = render_config
      expect(output).to include "$pdo_options_reports[\\PDO::MYSQL_ATTR_SSL_CERT] = \"/srv/deskpro/INSTANCE_DATA/mysql-reports-client.crt\";"
      expect(output).to include "$pdo_options_reports[\\PDO::MYSQL_ATTR_SSL_CA] = '/etc/ssl/certs';"
    end

    it "enables TLS on one connection only when only it has a certificate" do
      install_mysql_certs('mysql-read-ca.pem')
      output = render_config
      expect(output).not_to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL"
      expect(output).not_to include "$pdo_options_reports[\\PDO::MYSQL_ATTR_SSL"
      expect(output).to include "$pdo_options_read[\\PDO::MYSQL_ATTR_SSL_CA] = '/srv/deskpro/INSTANCE_DATA/mysql-read-ca.pem';"
    end

    it "takes verification per connection, falling back to the primary's setting" do
      install_mysql_certs('mysql-ca.pem')
      ENV['DESKPRO_DB_SSL_VERIFY_SERVER_CERT'] = 'true'
      ENV['DESKPRO_DB_READ_SSL_VERIFY_SERVER_CERT'] = 'false'
      output = render_config
      expect(output).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT] = true;"
      expect(output).to include "$pdo_options_read[\\PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT] = false;"
      expect(output).to include "$pdo_options_reports[\\PDO::MYSQL_ATTR_SSL_VERIFY_SERVER_CERT] = true;"
    end

    # An explicitly set value wins, including false. A replica on a trusted LAN
    # behind a primary reached over a WAN is a real topology, and silently
    # discarding the operator's `false` would be the kind of surprise this
    # whole design is trying to remove.
    it "honours an explicit false even when the primary has TLS on" do
      ENV['DESKPRO_DB_SSL_ENABLED'] = 'true'
      ENV['DESKPRO_DB_READ_SSL_ENABLED'] = 'false'
      output = render_config
      expect(output).to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL_CA] = '/etc/ssl/certs';"
      expect(output).to include "$pdo_options_read = [];"
      expect(output).not_to include "$pdo_options_read[\\PDO::MYSQL_ATTR_SSL"
      # unset, so it still cascades
      expect(output).to include "$pdo_options_reports[\\PDO::MYSQL_ATTR_SSL_CA] = '/etc/ssl/certs';"
    end

    it "enables TLS on one connection only from its own env var" do
      ENV['DESKPRO_DB_REPORTS_SSL_ENABLED'] = 'true'
      output = render_config
      expect(output).not_to include "$pdo_options[\\PDO::MYSQL_ATTR_SSL"
      expect(output).not_to include "$pdo_options_read[\\PDO::MYSQL_ATTR_SSL"
      expect(output).to include "$pdo_options_reports[\\PDO::MYSQL_ATTR_SSL_CA] = '/etc/ssl/certs';"
    end
  end
end
