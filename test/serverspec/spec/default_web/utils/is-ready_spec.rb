require 'spec_helper'
require 'fileutils'

def restore_run_state
  FileUtils.touch('/run/container-ready')
  FileUtils.remove_file('/run/container-running-installer', true)
  FileUtils.remove_file('/run/container-running-migrations', true)
end

describe "Check behaviour of is-ready utility" do
  before(:all) do
    system('is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  after(:each) do
    restore_run_state()
  end

  it "Blocks when using --wait", :slow do
    FileUtils.remove('/run/container-ready')

    t1=Time.now
    system('timeout 2 is-ready --wait')
    exit_code = $?.exitstatus
    t2=Time.now

    expect(exit_code).not_to eq 0
    expect(t2-t1).to be > 1.90
  end

  it "User supplied --timeout works", :slow do
    FileUtils.remove('/run/container-ready')

    t1=Time.now
    system('is-ready --wait --timeout 2')
    exit_code = $?.exitstatus
    t2=Time.now

    expect(exit_code).to eq 1
    expect(t2-t1).to be < 2.75
  end

  it "Does not block when not using --wait", :slow do
    FileUtils.remove('/run/container-ready')

    t1=Time.now
    system('is-ready')
    exit_code = $?.exitstatus
    t2=Time.now

    expect(exit_code).to eq 1
    expect(t2-t1).to be < 1
  end

  it "Does not block when already ready" do
    t1=Time.now
    system('timeout 2 is-ready')
    exit_code = $?.exitstatus
    t2=Time.now

    expect(exit_code).to eq 0
    expect(t2-t1).to be < 0.5

    # again but with --wait
    t1=Time.now
    system('timeout 2 is-ready --wait')
    exit_code = $?.exitstatus
    t2=Time.now

    expect(exit_code).to eq 0
    expect(t2-t1).to be < 0.5
  end

  it "Exits with 0 when ready" do
    system('is-ready')
    exit_code = $?.exitstatus
    expect(exit_code).to eq 0
  end

  it "Exits with 1 when not ready" do
    FileUtils.remove('/run/container-ready')
    system('is-ready')
    exit_code = $?.exitstatus
    expect(exit_code).to eq 1
  end

  it "Post-boot tasks dont matter without --check-tasks" do
    FileUtils.touch('/run/container-running-migrations')
    system('is-ready')
    exit_code = $?.exitstatus
    expect(exit_code).to eq 0
  end

  it "Post-boot tasks matter with --check-tasks" do
    FileUtils.touch('/run/container-running-migrations')
    system('is-ready --check-tasks')
    exit_code = $?.exitstatus
    expect(exit_code).to eq 1
  end
end
