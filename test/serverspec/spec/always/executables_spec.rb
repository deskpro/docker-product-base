require 'spec_helper'

executables = [
  "/usr/local/bin/composer",
  "/usr/local/bin/gomplate",
  "/usr/local/bin/vector",
  "/usr/bin/php",
  "/usr/sbin/php-fpm",

  "/usr/local/sbin/container-ready.sh",
  "/usr/local/sbin/tasksd",

  "/usr/local/bin/container-var",
  "/usr/local/bin/eval-tpl",
  "/usr/local/bin/healthcheck",
  "/usr/local/bin/is-ready",
  "/usr/local/bin/mysql-primary",
  "/usr/local/bin/mysql-read",
  "/usr/local/bin/mysqldump-primary",
  "/usr/local/bin/phpfpminfo",
  "/usr/local/bin/phpinfo",
  "/usr/local/bin/print-container-vars",
]

executables.each do |exe|
  describe file(exe) do
    it { should be_executable }
    it { should be_owned_by 'root' }
    it { should be_grouped_into 'root' }
  end
end
