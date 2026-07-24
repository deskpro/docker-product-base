require 'spec_helper'

describe "ES engine: DESKPRO_ES_ENGINE sets the search engine type" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  after(:all) do
    ENV.delete('DESKPRO_ES_ENGINE')
  end

  # Note: use RSpec's literal `include` matcher, not serverspec's `contain`
  # (which treats its argument as a regex).

  it "emits 'type' => 'opensearch' when DESKPRO_ES_ENGINE is opensearch" do
    ENV['DESKPRO_ES_ENGINE'] = 'opensearch'
    output = `eval-tpl -f /usr/local/share/deskpro/templates/deskpro-config.php.tmpl`
    expect(output).to include "'type' => 'opensearch'"
  end

  it "omits the 'type' key when DESKPRO_ES_ENGINE is unset" do
    ENV.delete('DESKPRO_ES_ENGINE')
    output = `eval-tpl -f /usr/local/share/deskpro/templates/deskpro-config.php.tmpl`
    expect(output).not_to include "'type' =>"
  end

  it "omits the 'type' key for a non-opensearch engine value" do
    ENV['DESKPRO_ES_ENGINE'] = 'elasticsearch'
    output = `eval-tpl -f /usr/local/share/deskpro/templates/deskpro-config.php.tmpl`
    expect(output).not_to include "'type' =>"
  end
end
