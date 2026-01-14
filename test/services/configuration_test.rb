# frozen_string_literal: true

require 'test_helper'

class ConfigurationTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir('slk-test')
    @paths = MockPaths.new(@tmpdir)
  end

  def teardown
    FileUtils.remove_entry(@tmpdir)
  end

  def test_returns_empty_hash_when_no_config_file
    config = SlackCli::Services::Configuration.new(paths: @paths)

    assert_nil config.primary_workspace
    assert_nil config.ssh_key
    assert_nil config.emoji_dir
  end

  def test_loads_existing_config
    write_config('primary_workspace' => 'myworkspace', 'ssh_key' => '/path/to/key')
    config = SlackCli::Services::Configuration.new(paths: @paths)

    assert_equal 'myworkspace', config.primary_workspace
    assert_equal '/path/to/key', config.ssh_key
  end

  def test_primary_workspace_setter
    config = SlackCli::Services::Configuration.new(paths: @paths)

    config.primary_workspace = 'newworkspace'
    assert_equal 'newworkspace', config.primary_workspace

    # Verify it was persisted
    saved = JSON.parse(File.read(@paths.config_file('config.json')))
    assert_equal 'newworkspace', saved['primary_workspace']
  end

  def test_ssh_key_setter
    config = SlackCli::Services::Configuration.new(paths: @paths)

    config.ssh_key = '/new/path/to/key'
    assert_equal '/new/path/to/key', config.ssh_key
  end

  def test_bracket_accessor
    write_config('custom_setting' => 'custom_value')
    config = SlackCli::Services::Configuration.new(paths: @paths)

    assert_equal 'custom_value', config['custom_setting']
  end

  def test_bracket_setter
    config = SlackCli::Services::Configuration.new(paths: @paths)

    config['new_key'] = 'new_value'
    assert_equal 'new_value', config['new_key']
  end

  def test_to_h_returns_copy
    write_config('key' => 'value')
    config = SlackCli::Services::Configuration.new(paths: @paths)

    hash = config.to_h
    hash['key'] = 'modified'

    # Original should be unchanged
    assert_equal 'value', config['key']
  end

  def test_handles_corrupted_json
    @paths.ensure_config_dir
    File.write(@paths.config_file('config.json'), 'not valid json')

    warnings = []
    config = SlackCli::Services::Configuration.new(paths: @paths)
    config.on_warning = ->(msg) { warnings << msg }

    # Access config to trigger loading
    config.primary_workspace

    assert_equal 1, warnings.size
    assert_match(/corrupted/i, warnings.first)
  end

  def test_warning_callback_called_on_corrupted_file
    @paths.ensure_config_dir
    File.write(@paths.config_file('config.json'), '{invalid')

    warning_received = nil
    config = SlackCli::Services::Configuration.new(paths: @paths)
    config.on_warning = ->(msg) { warning_received = msg }

    # Trigger load
    config.primary_workspace

    assert_match(/corrupted/i, warning_received)
  end

  def test_creates_config_dir_on_save
    config = SlackCli::Services::Configuration.new(paths: @paths)

    # Remove the config dir
    FileUtils.rmdir(@paths.config_dir) if Dir.exist?(@paths.config_dir)

    config.primary_workspace = 'test'

    assert Dir.exist?(@paths.config_dir)
  end

  def test_lazy_loads_config
    write_config('primary_workspace' => 'lazy')

    # Modify file after creating config object but before accessing
    config = SlackCli::Services::Configuration.new(paths: @paths)
    write_config('primary_workspace' => 'modified')

    # First access loads the modified value
    assert_equal 'modified', config.primary_workspace
  end

  private

  def write_config(data)
    @paths.ensure_config_dir
    File.write(@paths.config_file('config.json'), JSON.generate(data))
  end

  class MockPaths
    def initialize(tmpdir)
      @tmpdir = tmpdir
      @config_dir = File.join(tmpdir, 'config')
      @cache_dir = File.join(tmpdir, 'cache')
    end

    def config_dir
      @config_dir
    end

    def cache_dir
      @cache_dir
    end

    def config_file(name)
      File.join(@config_dir, name)
    end

    def cache_file(name)
      File.join(@cache_dir, name)
    end

    def ensure_config_dir
      FileUtils.mkdir_p(@config_dir)
    end

    def ensure_cache_dir
      FileUtils.mkdir_p(@cache_dir)
    end
  end
end
