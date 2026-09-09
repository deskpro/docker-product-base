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
    %w[mysql-client.crt mysql-client.key mysql-ca.pem]
      .map { |name| "/srv/deskpro/INSTANCE_DATA/#{name}" }
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
    ENV.delete('DESKPRO_DB_SSL_ENABLED')
    ENV.delete('DESKPRO_DB_SSL_VERIFY_SERVER_CERT')
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

  it "shares the SSL options with the read and reports connections" do
    install_mysql_certs('mysql-ca.pem')
    ENV['DESKPRO_DB_READ_HOST'] = 'mysql-read'
    ENV['DESKPRO_DB_REPORTS_HOST'] = 'mysql-reports'
    output = render_config
    expect(output.scan("'pdo_options' => $pdo_options ?? []").length).to eq 3
  ensure
    ENV.delete('DESKPRO_DB_READ_HOST')
    ENV.delete('DESKPRO_DB_REPORTS_HOST')
  end
end
