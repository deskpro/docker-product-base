require 'spec_helper'

describe "Ensure log files are owned by the correct group" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe user('vector') do
    it { should exist }
    it { should have_uid 1084 }
    it { should belong_to_primary_group 'logs_group' }
    it { should belong_to_group 'vector' }
    it { should belong_to_group 'adm' }
  end
end
