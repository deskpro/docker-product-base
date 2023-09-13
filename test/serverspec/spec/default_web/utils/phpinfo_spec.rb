require 'spec_helper'

describe "Check behaviour of phpinfo utility" do
  before(:all) do
    # need to wait for ready so that php-fpm is running for phpinfo --fpm commands
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  it "phpinfo should return phpinfo from CLI" do
    output = `phpinfo`
    exit_code = $?.exitstatus
    expect(exit_code).to eq 0
    expect(output).to include("PHP Version => 8.1.")
    # our phpinfo script does not include some parts of the output such as INFO_LICENSE, so just check that
    expect(output).to_not include("questions about PHP licensing, please contact license@php.net.")
  end

  it "phpinfo --fpm should return HTML phpinfo from php-fpm" do
    output = `phpinfo --fpm`
    exit_code = $?.exitstatus
    expect(exit_code).to eq 0
    expect(output).to include('<tr><td class="e">PHP Version </td><td class="v">8.1.')
  end
end
