require 'spec_helper'

describe "Check behaviour of phpfpminfo utility" do
  before(:all) do
    # need to wait for ready so that php-fpm is running for phpinfo --fpm commands
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  it "phpfpminfo should return info for all pools" do
    output = `phpfpminfo`
    exit_code = $?.exitstatus
    expect(exit_code).to eq 0

    expect(output).to include("[global]")
    expect(output).to include("[dp_default]")
    expect(output).to include("[dp_internal]")
    expect(output).to include("[dp_gql]")
    expect(output).to include("[dp_broadcaster]")
  end

  it "phpfpminfo should return info for only specified pool when using --pool" do
    output = `phpfpminfo --pool dp_internal`
    exit_code = $?.exitstatus
    expect(exit_code).to eq 0

    expect(output).to_not include("env[DP_FPM_POOL] = dp_default")
    expect(output).to include("env[DP_FPM_POOL] = dp_internal")
  end
end
