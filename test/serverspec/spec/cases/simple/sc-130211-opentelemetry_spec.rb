require 'spec_helper'

describe "Case SC-130211: Enable OTEL" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  after(:all) do
    FileUtils.remove_file('/etc/php/8.1/cli/conf.d/zzz-test.ini', true)
    ENV.delete('DESKPRO_ENABLE_OTEL')
  end

  it "DESKPRO_ENABLE_OTEL should activate opentelemetry extension" do
    ENV['DESKPRO_ENABLE_OTEL'] = 'true'

    output = `eval-tpl -f /etc/php/8.1/mods-available/deskpro-otel.ini.tmpl`
    expect(output).to contain "opentelemetry extension is enabled"

    `eval-tpl -f /etc/php/8.1/mods-available/deskpro-otel.ini.tmpl > /etc/php/8.1/cli/conf.d/zzz-test.ini`
    output = `php --ri opentelemetry`
    expect(output).to contain "opentelemetry hooks => enabled"
  end
end
