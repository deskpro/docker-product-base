require 'spec_helper'
require 'fileutils'

def parse_health_output(output)
  result = { :tests => [], :results => {} }

  output.split("\n").map { |line|
    m = line.match(/<(?<type>TEST|RESULT):(?<tag>\w+)(:(?<result>OK|FAIL))?>/)
    if m
      result[:tests].push(m[:tag]) unless result[:tests].include? m[:tag]
      if m[:type] == "RESULT"
        result[:results][m[:tag]] = m[:result]
      end
    else
      if line.include? "<TEST" or line.include? "<RESULT"
        raise "Failed to parse line: #{line}"
      end
    end
  }

  return result
end

describe "Check behaviour of healthcheck utility" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  before(:each) do
    FileUtils.touch('/run/container-ready')
    FileUtils.remove_file('/run/container-running-installer', true)
    FileUtils.remove_file('/run/container-running-migrations', true)
    FileUtils.remove_file('/run/container-config/HEALTHCHECK_TEST_DISCOVER', true)
    FileUtils.remove_file('/run/container-config/HEALTHCHECK_TEST_DB_CONNECTION', true)

    ENV.delete('HEALTHCHECK_TEST_DISCOVER')
    ENV.delete('HEALTHCHECK_TEST_DB_CONNECTION')
  end

  after(:each) do
    FileUtils.touch('/run/container-ready')
    FileUtils.remove_file('/run/container-running-installer', true)
    FileUtils.remove_file('/run/container-running-migrations', true)
    FileUtils.remove_file('/run/container-config/HEALTHCHECK_TEST_DISCOVER', true)
    FileUtils.remove_file('/run/container-config/HEALTHCHECK_TEST_DB_CONNECTION', true)

    ENV.delete('HEALTHCHECK_TEST_DISCOVER')
    ENV.delete('HEALTHCHECK_TEST_DB_CONNECTION')
  end

  # This suite (default_web) has web service running. So default
  # tests should be --test-ready and --test-http
  it "Check default tests" do
    output = `healthcheck -v`
    exit_code = $?.exitstatus
    result = parse_health_output(output)

    expect(exit_code).to eq 0
    expect(result[:tests]).to eq(["ready", "http", "phpfpm"])
  end

  it "Check --only will disable defaults" do
    output = `healthcheck -v --only`
    exit_code = $?.exitstatus
    result = parse_health_output(output)

    expect(exit_code).to eq 0
    expect(result[:tests]).to eq([])

    output = `healthcheck -v --only --test-ready`
    exit_code = $?.exitstatus
    result = parse_health_output(output)

    expect(exit_code).to eq 0
    expect(result[:tests]).to eq(["ready"])
  end

  it "Check negating a test with --no-test-XXX" do
    output = `healthcheck -v --no-test-http`
    exit_code = $?.exitstatus
    result = parse_health_output(output)

    expect(exit_code).to eq 0
    expect(result[:tests]).to eq(["ready"])
  end

  it "Check setting env vars to enable tests" do
    ENV['HEALTHCHECK_TEST_DISCOVER'] = 'true'
    ENV['HEALTHCHECK_TEST_DB_CONNECTION'] = 'true'
    output = `healthcheck -v`
    exit_code = $?.exitstatus
    result = parse_health_output(output)

    expect(result[:tests]).to eq(["ready", "http", "phpfpm", "discover", "dbconn"])
  end

  it "Check --ignore-env discards env var values" do
    ENV['HEALTHCHECK_TEST_DISCOVER'] = 'true'
    ENV['HEALTHCHECK_TEST_DB_CONNECTION'] = 'true'
    output = `healthcheck -v --ignore-env`
    exit_code = $?.exitstatus
    result = parse_health_output(output)

    expect(result[:tests]).to eq(["ready", "http", "phpfpm"])
  end

  it "Check env-based defaults via container-vars" do
    File.write("/run/container-config/HEALTHCHECK_TEST_DISCOVER", "true")
    File.write("/run/container-config/HEALTHCHECK_TEST_DB_CONNECTION", "true")

    output = `healthcheck -v`
    exit_code = $?.exitstatus
    result = parse_health_output(output)

    expect(result[:tests]).to eq(["ready", "http", "phpfpm", "discover", "dbconn"])
  end

  it "Check simulated discover" do
    output = `healthcheck -v --only --test-discover`
    exit_code = $?.exitstatus
    result = parse_health_output(output)

    expect(exit_code).to eq 0
    expect(result[:tests]).to eq(["discover"])
  end

  it "Check that running migrations pass healthcheck" do
    FileUtils.touch('/run/container-running-migrations')
    output = `healthcheck -v --test-discover --test-db`
    exit_code = $?.exitstatus
    result = parse_health_output(output)

    expect(exit_code).to eq 0
    # only the ready test is done because it short-circuits the others while migrations run
    expect(result[:tests]).to eq(["ready"])
  end

  it "Check that running installer pass healthcheck" do
    FileUtils.touch('/run/container-running-installer')
    output = `healthcheck -v --test-discover --test-db`
    exit_code = $?.exitstatus
    result = parse_health_output(output)

    expect(exit_code).to eq 0
    # only the ready test is done because it short-circuits the others while migrations run
    expect(result[:tests]).to eq(["ready"])
  end

  it "Check readiness healthcheck fails without container ready" do
    FileUtils.remove('/run/container-ready')
    output = `healthcheck -v`
    exit_code = $?.exitstatus
    result = parse_health_output(output)

    expect(exit_code).to_not eq 0
    expect(result[:tests]).to eq(["ready"])
  end

  it "Blocks when using --wait", :slow do
    FileUtils.remove('/run/container-ready')

    t1=Time.now
    system('timeout 2 healthcheck --wait')
    exit_code = $?.exitstatus
    t2=Time.now

    expect(exit_code).not_to eq 0
    expect(t2-t1).to be > 1.90
  end

  it "User supplied --timeout works", :slow do
    FileUtils.remove('/run/container-ready')

    t1=Time.now
    system('healthcheck --wait --timeout 2')
    exit_code = $?.exitstatus
    t2=Time.now

    expect(exit_code).to eq 1
    expect(t2-t1).to be < 2.75
  end
end
