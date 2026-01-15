# frozen_string_literal: true

require 'test_helper'

class ConfigCommandTest < Minitest::Test
  def setup
    @io = StringIO.new
    @err = StringIO.new
    @output = Slk::Formatters::Output.new(io: @io, err: @err, color: false)
    @config = MockConfig.new
  end

  def create_runner(workspaces: nil)
    token_store = Object.new
    workspace_list = workspaces || []

    token_store.define_singleton_method(:workspace) do |name|
      workspace_list.find { |w| w.name == name }
    end
    token_store.define_singleton_method(:all_workspaces) { workspace_list }
    token_store.define_singleton_method(:workspace_names) { workspace_list.map(&:name) }
    token_store.define_singleton_method(:empty?) { workspace_list.empty? }
    token_store.define_singleton_method(:on_warning=) { |_| nil }
    token_store.define_singleton_method(:on_info=) { |_| nil }
    token_store.define_singleton_method(:add) { |_name, _token, _cookie| nil }
    token_store.define_singleton_method(:migrate_encryption) { |_old, _new| nil }

    preset_store = Object.new
    preset_store.define_singleton_method(:on_warning=) { |_| nil }

    cache_store = Object.new
    cache_store.define_singleton_method(:on_warning=) { |_| nil }

    Slk::Runner.new(
      output: @output,
      config: @config,
      token_store: token_store,
      preset_store: preset_store,
      cache_store: cache_store
    )
  end

  def test_show_displays_config
    @config.data['primary_workspace'] = 'myworkspace'
    @config.data['ssh_key'] = '/path/to/key'

    runner = create_runner
    command = Slk::Commands::Config.new(['show'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'myworkspace'
    assert_includes @io.string, '/path/to/key'
  end

  def test_show_default_action
    runner = create_runner
    command = Slk::Commands::Config.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'Configuration'
  end

  def test_get_value
    @config.data['emoji_dir'] = '/custom/emoji'

    runner = create_runner
    command = Slk::Commands::Config.new(%w[get emoji_dir], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, '/custom/emoji'
  end

  def test_get_value_not_set
    runner = create_runner
    command = Slk::Commands::Config.new(%w[get nonexistent], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, '(not set)'
  end

  def test_set_value
    runner = create_runner
    command = Slk::Commands::Config.new(['set', 'emoji_dir', '/new/path'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_equal '/new/path', @config.data['emoji_dir']
    assert_includes @io.string, 'Set'
  end

  def test_set_ssh_key_validates_key_type
    Dir.mktmpdir do |dir|
      # Create an ECDSA key (unsupported by age)
      key_path = "#{dir}/ecdsa_key"
      File.write("#{key_path}.pub", 'ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTI... user@host')

      # Use a mock token store that will call migrate_encryption
      token_store = Object.new
      token_store.define_singleton_method(:workspace_names) { [] }
      token_store.define_singleton_method(:empty?) { true }
      token_store.define_singleton_method(:on_warning=) { |_| nil }
      token_store.define_singleton_method(:on_info=) { |_| nil }

      # migrate_encryption should validate key type and raise
      encryption = Slk::Services::Encryption.new
      token_store.define_singleton_method(:migrate_encryption) do |_old, new_key|
        encryption.validate_key_type!(new_key) if new_key
      end

      preset_store = Object.new
      preset_store.define_singleton_method(:on_warning=) { |_| nil }

      cache_store = Object.new
      cache_store.define_singleton_method(:on_warning=) { |_| nil }

      runner = Slk::Runner.new(
        output: @output,
        config: @config,
        token_store: token_store,
        preset_store: preset_store,
        cache_store: cache_store
      )

      command = Slk::Commands::Config.new(['set', 'ssh_key', key_path], runner: runner)
      result = command.execute

      assert_equal 1, result
      assert_includes @err.string, 'Unsupported SSH key type'
    end
  end

  def test_set_ssh_key_expands_path
    Dir.mktmpdir do |dir|
      # Create a valid ed25519 key
      key_path = "#{dir}/test_key"
      File.write("#{key_path}.pub", 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@host')

      runner = create_runner
      command = Slk::Commands::Config.new(['set', 'ssh_key', key_path], runner: runner)
      result = command.execute

      assert_equal 0, result
      # Path should be expanded (absolute)
      assert @config.data['ssh_key'].start_with?('/')
    end
  end

  def test_set_ssh_key_empty_clears_key
    @config.data['ssh_key'] = nil # No previous key

    runner = create_runner
    command = Slk::Commands::Config.new(['set', 'ssh_key', ''], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_nil @config.data['ssh_key']
    assert_includes @io.string, 'Cleared ssh_key'
  end

  def test_help_option
    runner = create_runner
    command = Slk::Commands::Config.new(['--help'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'slk config'
    assert_includes @io.string, 'show'
    assert_includes @io.string, 'setup'
    assert_includes @io.string, 'get'
    assert_includes @io.string, 'set'
  end

  class MockConfig
    attr_accessor :data

    def initialize
      @data = {}
    end

    def primary_workspace
      @data['primary_workspace']
    end

    def primary_workspace=(value)
      @data['primary_workspace'] = value
    end

    def ssh_key
      @data['ssh_key']
    end

    def ssh_key=(value)
      @data['ssh_key'] = value
    end

    def emoji_dir
      @data['emoji_dir']
    end

    def [](key)
      @data[key]
    end

    def []=(key, value)
      @data[key] = value
    end

    def on_warning=(callback); end
  end
end
