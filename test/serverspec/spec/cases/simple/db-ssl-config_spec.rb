require 'spec_helper'

# With nothing mounted under /deskpro/ssl/mysql/ the database connection must
# stay exactly as it was: no TLS options at all. The positive cases live in
# spec/scenarios/db_ssl_certs, which mounts real certs.
describe "DB SSL config: no certs mounted means no TLS options" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  # Note: use RSpec's literal `include` matcher, not serverspec's `contain`.
  # `contain` treats its argument as a regex, and the rendered PHP contains
  # metacharacters ($, [, ]) that would break matching.

  describe file('/srv/deskpro/INSTANCE_DATA/mysql-ca.crt') do
    it { should_not exist }
  end

  describe file('/srv/deskpro/INSTANCE_DATA/mysql-client.crt') do
    it { should_not exist }
  end

  it "emits an empty pdo_options" do
    output = `eval-tpl -f /usr/local/share/deskpro/templates/deskpro-config.php.tmpl`
    expect(output).to include "$pdo_options = [];"
    expect(output).not_to include "MYSQL_ATTR_SSL_"
  end

  # MariaDB's client defaults ssl and ssl-verify-server-cert to on, so the
  # no-cert case has to switch them off rather than say nothing.
  it "switches the CLI clients' TLS off explicitly" do
    output = `eval-tpl -f /usr/local/share/deskpro/templates/user.my.cnf.tmpl`
    expect(output).to include "ssl=0"
    expect(output).not_to include "ssl-ca="
    expect(output).not_to include "ssl-cert="
  end

  # Regression: SSL_CA used to be set to the /etc/ssl/certs *directory*, but the
  # attribute maps to mysql_ssl_set()'s `ca` param, which must be a file. The
  # directory form would be MYSQL_ATTR_SSL_CAPATH.
  it "never points SSL_CA at a directory" do
    output = `eval-tpl -f /usr/local/share/deskpro/templates/deskpro-config.php.tmpl`
    expect(output).not_to include "MYSQL_ATTR_SSL_CA] = '/etc/ssl/certs';"
  end
end
