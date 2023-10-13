require 'spec_helper'

describe "Case SC-130148: Default ES values" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  after(:all) do
    ENV.delete('DESKPRO_ES_TENANT_ID')
    ENV.delete('DESKPRO_ES_INDEX_NAME')
  end

  it "DESKPRO_ES_TENANT_ID will suffix _tenant if it conflicts with DESKPRO_ES_INDEX_NAME" do
    ENV['DESKPRO_ES_INDEX_NAME'] = 'deskpro'
    ENV['DESKPRO_ES_TENANT_ID'] = 'deskpro'
    output = `eval-tpl -f /etc/templates/deskpro-config.php.tmpl`
    expect(output).to contain "'index_name' => 'deskpro'"
    expect(output).to contain "'tenant_id' => 'deskpro_tenant'"
  end

  it "DESKPRO_ES_TENANT_ID will be used as-is if there is no conflict" do
    ENV['DESKPRO_ES_INDEX_NAME'] = 'deskpro'
    ENV['DESKPRO_ES_TENANT_ID'] = 'foo'
    output = `eval-tpl -f /etc/templates/deskpro-config.php.tmpl`
    expect(output).to contain "'index_name' => 'deskpro'"
    expect(output).to contain "'tenant_id' => 'foo'"
  end
end
