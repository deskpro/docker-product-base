require 'spec_helper'

# Same container as 04, restarted after /deskpro/ssl/mysql/read/ was emptied
# on the host.
#
# INSTANCE_DATA survives a restart, so without explicit reaping last boot's
# mysql-read-ca.pem would still be sitting there - and because certificates are
# directory-scoped, that stale file would keep the read connection pinned to a
# CA the operator has already removed. 20-certs.sh clears its own copies before
# installing, so an unmounted directory reads as "supplied nothing".
describe "MySQL TLS: certificates removed from a mount are reaped at boot" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe file('/srv/deskpro/INSTANCE_DATA/mysql-read-ca.pem') do
    it { should_not exist }
  end

  # the primary and reports mounts are untouched, so their copies stay
  describe file('/srv/deskpro/INSTANCE_DATA/mysql-ca.pem') do
    it { should be_file }
  end

  describe file('/srv/deskpro/INSTANCE_DATA/mysql-reports-ca.pem') do
    it { should be_file }
  end

  it "falls the read connection back to the primary's certificates" do
    config = File.read('/srv/deskpro/INSTANCE_DATA/deskpro-config.php')
    expect(config).to include "$pdo_options_read[\\PDO::MYSQL_ATTR_SSL_CA] = '/srv/deskpro/INSTANCE_DATA/mysql-ca.pem';"
    expect(config).to include "$pdo_options_read[\\PDO::MYSQL_ATTR_SSL_CERT] = \"/srv/deskpro/INSTANCE_DATA/mysql-client.crt\";"
  end
end
