require 'spec_helper'

# The nginx.org package ships a
# default site at /etc/nginx/conf.d/default.conf that listens on port 80 and
# shadows Deskpro's own server blocks, causing instance-API requests to 404.
# The Dockerfile removes it after install. A future nginx version bump (or any
# reinstall that re-adds the file) must not bring it back, so assert it is gone.
describe file('/etc/nginx/conf.d/default.conf') do
  it { should_not exist }
end
