require 'spec_helper'

describe user('dp_app') do
  it { should exist }
  it { should have_uid 1083 }
  it { should belong_to_primary_group 'dp_app' }
  it { should have_login_shell '/bin/false' }
end

describe user('vector') do
  it { should exist }
  it { should have_uid 1084 }
  it { should belong_to_primary_group 'adm' }
  it { should have_login_shell '/bin/false' }
end

describe user('nginx') do
  it { should exist }
  it { should have_uid 1085 }
  it { should belong_to_primary_group 'nginx' }
end
