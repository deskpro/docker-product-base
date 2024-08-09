require 'spec_helper'

describe file('/etc/php/8.3') do
  it { should exist }
  it { should be_directory }
end

describe file('/usr/local/share/deskpro/container-var-reference.json') do
  it { should exist }
  it { should be_owned_by 'root' }
  it { should be_grouped_into 'root' }
  its(:content_as_json) { should_not be_empty }
end

describe file('/usr/local/share/deskpro/container-public-var-list') do
  it { should exist }
  it { should be_owned_by 'root' }
  it { should be_grouped_into 'root' }
end

describe file('/usr/local/share/deskpro/container-private-var-list') do
  it { should exist }
  it { should be_owned_by 'root' }
  it { should be_grouped_into 'root' }
end

describe file('/usr/local/share/deskpro/container-setenv-var-list') do
  it { should exist }
  it { should be_owned_by 'root' }
  it { should be_grouped_into 'root' }
end

describe file('/usr/local/share/deskpro/container-var-list') do
  it { should exist }
  it { should be_owned_by 'root' }
  it { should be_grouped_into 'root' }
end

describe file('/usr/local/share/deskpro/phpinfo.php') do
  it { should exist }
  it { should be_owned_by 'root' }
  it { should be_grouped_into 'root' }
end

describe file('/var/log/nginx') do
  it { should be_directory }
  it { should be_owned_by 'nginx' }
  it { should be_grouped_into 'adm' }

  it { should be_readable.by('owner') }
  it { should be_readable.by('group') }
  it { should be_writable.by('owner') }
  it { should_not be_writable.by('others') }
end

describe file('/var/log/php') do
  it { should be_directory }
  it { should be_owned_by 'dp_app' }
  it { should be_grouped_into 'adm' }

  it { should be_readable.by('owner') }
  it { should be_readable.by('group') }
  it { should be_writable.by('owner') }
  it { should_not be_writable.by('others') }
end

describe file('/var/log/deskpro') do
  it { should be_directory }
  it { should be_owned_by 'dp_app' }
  it { should be_grouped_into 'adm' }

  it { should be_readable.by('owner') }
  it { should be_readable.by('group') }
  it { should be_writable.by('owner') }
  it { should_not be_writable.by('others') }
end

describe file('/var/lib/vector') do
  it { should be_directory }
  it { should be_owned_by 'vector' }
  it { should be_grouped_into 'adm' }

  it { should be_readable.by('owner') }
  it { should be_readable.by('group') }
  it { should be_writable.by('owner') }
  it { should_not be_writable.by('others') }
end

describe file('/srv/deskpro/INSTANCE_DATA') do
  it { should be_directory }
  it { should be_owned_by 'root' }
  it { should be_grouped_into 'root' }
  it { should_not be_writable.by('others') }
end

describe file('/srv/deskpro/INSTANCE_DATA/deskpro-config.d') do
  it { should be_directory }
  it { should be_owned_by 'root' }
  it { should be_grouped_into 'root' }
  it { should_not be_writable.by('others') }
end
