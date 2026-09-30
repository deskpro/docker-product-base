require 'spec_helper'
require 'fileutils'

describe "Check behaviour of is-ready utility" do
  before(:all) do
    system('is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  after(:each) do
    FileUtils.touch('/run/container-ready')
    FileUtils.remove_file('/run/container-running-installer', true)
    FileUtils.remove_file('/run/container-running-migrations', true)
    FileUtils.remove_file('/run/container-running-auto-run-tools', true)
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

  it "auto-run-tools marker matters with --check-tasks" do
    FileUtils.touch('/run/container-running-auto-run-tools')
    system('is-ready --check-tasks')
    expect($?.exitstatus).to eq 1
  end

  it "auto-run-tools marker doesnt matter without --check-tasks" do
    FileUtils.touch('/run/container-running-auto-run-tools')
    system('is-ready')
    expect($?.exitstatus).to eq 0
  end

  it "--wait --check-tasks blocks until the auto-run-tools marker is cleared", :slow do
    FileUtils.touch('/run/container-running-auto-run-tools')
    Thread.new { sleep 2; FileUtils.remove_file('/run/container-running-auto-run-tools', true) }

    t1 = Time.now
    system('is-ready --check-tasks --wait --timeout 10')
    expect($?.exitstatus).to eq 0
    expect(Time.now - t1).to be >= 1.5
  end

  # Regression guard for the readiness TOCTOU: container-ready.sh must flag pending tasks
  # before it publishes /run/container-ready, and only clear the flag after auto_run_tools.
  it "container-ready.sh sets the marker before ready and clears it after auto_run_tools" do
    lines = File.readlines('/usr/local/sbin/container-ready.sh').map(&:strip)
    idx = ->(pat) { lines.index { |l| l =~ pat } }
    set_marker   = idx.call(/\Asave_sentinel_runfile auto-run-tools\z/)
    write_ready  = idx.call(%r{\Adate .*> /run/container-ready\z})
    run_tools    = idx.call(/\Aauto_run_tools\z/)
    clear_marker = idx.call(/\Aremove_sentinel_runfile auto-run-tools\z/)

    expect([set_marker, write_ready, run_tools, clear_marker]).to all(be_a(Integer))
    expect(set_marker).to be < write_ready
    expect(write_ready).to be < run_tools
    expect(run_tools).to be < clear_marker
  end
end
