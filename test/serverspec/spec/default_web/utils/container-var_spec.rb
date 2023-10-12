require 'spec_helper'
require 'fileutils'

describe "Check behaviour of container-var utility" do
  before(:each) do
    File.write("/run/container-config/TEST_VAR", "foo")
    ENV.delete('TEST_VAR')

    File.write("/run/container-config/TEST_VAR_EMPTY", "")
    ENV.delete('TEST_VAR_EMPTY')

    FileUtils.remove_file('/run/container-config/TEST_VAR_MISSING', true)
    ENV.delete('TEST_VAR_MISSING')
  end

  it "Variable loads from current env if set" do
    ENV['TEST_VAR'] = 'bar';
    output = `container-var TEST_VAR`
    exit_code = $?.exitstatus
    expect(exit_code).to eq 0
    expect(output).to eq("bar")
  end

  it "Variable loads from /run/container-config if --ignore-env is used" do
    ENV['TEST_VAR'] = 'bar';
    output = `container-var --ignore-env TEST_VAR`
    exit_code = $?.exitstatus
    expect(exit_code).to eq 0
    expect(output).to eq("foo")
  end

  it "A missing variable should return error status" do
    output = `container-var -r TEST_VAR_MISSING`
    exit_code = $?.exitstatus
    expect(exit_code).to eq 33
  end

  it "A variable with an empty value is still considered set" do
    output = `container-var -r TEST_VAR_EMPTY`
    exit_code = $?.exitstatus
    expect(exit_code).to eq 0
    expect(output).to eq("")
  end

  it "A missing variable with a default value will return the default value" do
    output = `container-var -r --default hello TEST_VAR_MISSING`
    exit_code = $?.exitstatus
    expect(exit_code).to eq 0
    expect(output).to eq("hello")
  end

  it "A variable set only in the environment (and not in /run/container-config) is considered set" do
    ENV['TEST_VAR_MISSING'] = 'foo';
    output = `container-var -r TEST_VAR_MISSING`
    exit_code = $?.exitstatus
    expect(exit_code).to eq 0
    expect(output).to eq("foo")
  end

  it "A variable set only in the environment is considered unset if --ignore-env is used" do
    ENV['TEST_VAR_MISSING'] = 'foo';
    output = `container-var -r --ignore-env TEST_VAR_MISSING`
    exit_code = $?.exitstatus
    expect(exit_code).to eq 33
  end

  it "A missing variable is considered empty" do
    output = `container-var --not-empty TEST_VAR_MISSING`
    exit_code = $?.exitstatus
    expect(exit_code).to eq 34
  end

  it "A missing variable with a non-empty default value should pass the --not-empty check" do
    output = `container-var --not-empty --default hello TEST_VAR_MISSING`
    exit_code = $?.exitstatus
    expect(exit_code).to eq 0
    expect(output).to eq("hello")
  end

  it "A variable with an empty value should fail with --not-empty" do
    output = `container-var --not-empty TEST_VAR_EMPTY`
    exit_code = $?.exitstatus
    expect(exit_code).to eq 34
  end

  it "A variable overriden to an empty value in the environment should fail --not-empty" do
    ENV['TEST_VAR'] = '';
    output = `container-var --not-empty TEST_VAR`
    exit_code = $?.exitstatus
    expect(exit_code).to eq 34
  end

  it "A variable overriden to an empty value in the environment should be ignored with --ignore-env" do
    ENV['TEST_VAR'] = '';
    output = `container-var --ignore-env --not-empty TEST_VAR`
    exit_code = $?.exitstatus
    expect(exit_code).to eq 0
    expect(output).to eq("foo")
  end

  it "An empty variable will return the default value when --not-empty is used" do
    ENV['TEST_VAR'] = '';
    output = `container-var --not-empty -l hello TEST_VAR`
    exit_code = $?.exitstatus
    expect(exit_code).to eq 0
    expect(output).to eq("hello")
  end

  it "An missing variable will return the default value when --not-empty and --required are used together" do
    output = `container-var --required --not-empty -l hello TEST_VAR_MISSING`
    exit_code = $?.exitstatus
    expect(exit_code).to eq 0
    expect(output).to eq("hello")
  end
end
