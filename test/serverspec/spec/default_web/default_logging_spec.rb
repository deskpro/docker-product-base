require 'spec_helper'

describe "Default logging options" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  it "should log in logfmt by default" do
    expect(ENV['LOGS_OUTPUT_FORMAT']).to eq('logfmt')
  end

  describe file('/var/log/docker-boot.log') do
    it { should exist }
    it { should be_owned_by 'root' }
    it { should be_grouped_into 'root' }
    its(:content) { should match /STARTING DESKPRO CONTAINER/ }
    its(:content) { should match /Starting services/ }
  end
end
