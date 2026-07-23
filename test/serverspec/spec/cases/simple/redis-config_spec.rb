require 'spec_helper'

describe "Redis config: env vars render $CONFIG['redis']" do
  before(:all) do
    system('/usr/local/bin/is-ready --check-tasks --wait --timeout 60 -v') or raise "is-ready failed"
  end

  after(:all) do
    ENV.delete('DESKPRO_REDIS_URL')
    ENV.delete('DESKPRO_REDIS_HOST')
    ENV.delete('DESKPRO_REDIS_USER')
    ENV.delete('DESKPRO_REDIS_PASS')
    ENV.delete('DESKPRO_REDIS_PORT')
    ENV.delete('DESKPRO_REDIS_DATABASE')
    ENV.delete('DESKPRO_REDIS_PREFIX')
  end

  it "renders the redis block with host and default port when DESKPRO_REDIS_HOST is set" do
    ENV['DESKPRO_REDIS_HOST'] = 'redis'
    output = `eval-tpl -f /usr/local/share/deskpro/templates/deskpro-config.php.tmpl`
    expect(output).to contain "$CONFIG['redis'] ="
    expect(output).to contain "'host'     => 'redis'"
    expect(output).to contain "'port'     => '6379'"
    expect(output).to contain "'database' => '0'"
  end

  it "emits the prefix key only when DESKPRO_REDIS_PREFIX is set" do
    ENV['DESKPRO_REDIS_HOST'] = 'redis'
    ENV['DESKPRO_REDIS_PREFIX'] = 'dp_'
    output = `eval-tpl -f /usr/local/share/deskpro/templates/deskpro-config.php.tmpl`
    expect(output).to contain "'prefix'   => 'dp_'"
  end

  it "omits the prefix key when DESKPRO_REDIS_PREFIX is unset" do
    ENV['DESKPRO_REDIS_HOST'] = 'redis'
    ENV.delete('DESKPRO_REDIS_PREFIX')
    output = `eval-tpl -f /usr/local/share/deskpro/templates/deskpro-config.php.tmpl`
    expect(output).not_to contain "'prefix'"
  end

  it "does not render the redis block when no redis vars are set" do
    ENV.delete('DESKPRO_REDIS_HOST')
    ENV.delete('DESKPRO_REDIS_URL')
    output = `eval-tpl -f /usr/local/share/deskpro/templates/deskpro-config.php.tmpl`
    expect(output).not_to contain "$CONFIG['redis'] ="
  end
end
