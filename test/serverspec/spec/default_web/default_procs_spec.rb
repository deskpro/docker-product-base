require 'spec_helper'

describe "Check running processes" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  describe "Ensure AUTO tasks are not running by default" do
    describe command('container-var AUTO_RUN_INSTALLER') do
      its(:stdout) { should be_empty }
    end

    describe command('container-var AUTO_RUN_MIGRATIONS') do
      its(:stdout) { should be_empty }
    end

    describe file('/var/log/docker-boot.log') do
      it { should exist }
      its(:content) { should_not contain "Running: bin/install" }
      its(:content) { should_not contain "Running: php tools/migrations/artisan migrations:exec" }
    end
  end

  describe "Ensure processes are running" do
    describe command("supervisorctl status") do
      its(:stdout) { should match /nginx\s+RUNNING/ }
      its(:stdout) { should match /php_fpm\s+RUNNING/ }
      its(:stdout) { should match /tasks\s+STOPPED/ }

      its(:stdout) { should match /email_collect:.*\s+STOPPED/ }
      its(:stdout) { should match /email_process:.*\s+STOPPED/ }

      its(:stdout) { should match /vector\s+RUNNING/ }
      its(:stdout) { should match /exit_on_failure\s+RUNNING/ }
      its(:stdout) { should match /rotate_logs\s+RUNNING/ }
    end

    describe port(80) do
      it { should be_listening }
    end

    describe port(443) do
      it { should be_listening }
    end

    describe port(10001) do
      it { should be_listening }
    end
  end
end
