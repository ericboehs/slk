# frozen_string_literal: true

require 'test_helper'
require 'stringio'
require 'slk/commands/ssh_key_manager'

class SshKeyManagerTest < Minitest::Test
  def setup
    @output = StringIO.new
  end

  def test_set_expands_path
    skip unless can_create_test_ssh_key?

    with_temp_setup do |_dir, config, token_store, key_path|
      # Track what path was set
      set_path = nil
      config.define_singleton_method(:[]=) { |k, v| set_path = v if k == 'ssh_key' }

      manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)

      result = manager.set(key_path)

      assert result[:success]
      # Verify the path was stored (File.expand_path is called internally)
      assert set_path&.start_with?('/'), 'Path should be absolute'
    end
  end

  def test_set_rejects_pub_key_file
    with_mock_setup do |config, token_store|
      manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)

      result = manager.set('/path/to/key.pub')

      refute result[:success]
      assert_match(/private key path, not the public key/, result[:error])
    end
  end

  def test_set_returns_error_on_encryption_error
    with_mock_setup do |config, token_store|
      token_store.define_singleton_method(:migrate_encryption) { |_o, _n| raise Slk::EncryptionError, 'Key invalid' }

      manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)

      result = manager.set('/path/to/key')

      refute result[:success]
      assert_equal 'Key invalid', result[:error]
    end
  end

  def test_set_returns_error_on_file_not_found
    with_mock_setup do |config, token_store|
      token_store.define_singleton_method(:migrate_encryption) do |_o, _n|
        raise Errno::ENOENT, 'No such file'
      end

      manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)

      result = manager.set('/path/to/key')

      refute result[:success]
      assert_match(/File not found/, result[:error])
    end
  end

  def test_set_returns_error_on_permission_denied
    with_mock_setup do |config, token_store|
      token_store.define_singleton_method(:migrate_encryption) do |_o, _n|
        raise Errno::EACCES, 'Permission denied'
      end

      manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)

      result = manager.set('/path/to/key')

      refute result[:success]
      assert_match(/Permission denied/, result[:error])
    end
  end

  def test_set_returns_success_with_message
    with_mock_setup do |config, token_store|
      manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)

      result = manager.set('/path/to/key')

      assert result[:success]
      # On Windows, path gets expanded to D:/path/to/key
      assert_match(/Set ssh_key = .*path.to.key/, result[:message])
    end
  end

  def test_unset_clears_ssh_key
    with_mock_setup do |config, token_store|
      config.define_singleton_method(:ssh_key) { '/old/key' }

      manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)

      result = manager.unset

      assert result[:success]
      assert_match(/Cleared ssh_key/, result[:message])
    end
  end

  def test_unset_returns_error_on_encryption_error
    with_mock_setup do |config, token_store|
      config.define_singleton_method(:ssh_key) { '/old/key' }
      token_store.define_singleton_method(:migrate_encryption) { |_o, _n| raise Slk::EncryptionError, 'Decrypt failed' }

      manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)

      result = manager.unset

      refute result[:success]
      assert_equal 'Decrypt failed', result[:error]
    end
  end

  def test_on_info_callback_is_propagated
    with_mock_setup do |config, token_store|
      info_messages = []

      # Create a token store that calls the info callback
      token_store.define_singleton_method(:on_info=) { |cb| @on_info = cb }
      token_store.define_singleton_method(:migrate_encryption) do |_o, _n|
        @on_info&.call('Migration info')
      end

      manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)
      manager.on_info = ->(msg) { info_messages << msg }

      manager.set('/path/to/key')

      assert_includes info_messages, 'Migration info'
    end
  end

  def test_on_warning_callback_is_propagated
    with_mock_setup do |config, token_store|
      warning_messages = []

      # Create a token store that calls the warning callback
      token_store.define_singleton_method(:on_warning=) { |cb| @on_warning = cb }
      token_store.define_singleton_method(:migrate_encryption) do |_o, _n|
        @on_warning&.call('Migration warning')
      end

      manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)
      manager.on_warning = ->(msg) { warning_messages << msg }

      manager.set('/path/to/key')

      assert_includes warning_messages, 'Migration warning'
    end
  end

  def test_set_clears_key_on_empty_string
    with_mock_setup do |config, token_store|
      cleared = false
      config.define_singleton_method(:[]=) do |k, v|
        cleared = true if k == 'ssh_key' && v.nil?
      end

      manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)

      result = manager.set('')

      assert result[:success]
      assert cleared, 'Config ssh_key should be set to nil'
    end
  end

  private

  def with_mock_setup
    config = Object.new
    config.define_singleton_method(:ssh_key) { nil }
    config.define_singleton_method(:[]=) { |_k, _v| nil }

    token_store = Object.new
    token_store.define_singleton_method(:on_info=) { |_cb| nil }
    token_store.define_singleton_method(:on_warning=) { |_cb| nil }
    token_store.define_singleton_method(:on_prompt_pub_key=) { |_cb| nil }
    token_store.define_singleton_method(:migrate_encryption) { |_o, _n| nil }

    yield config, token_store
  end

  def with_temp_setup
    skip unless can_create_test_ssh_key?

    Dir.mktmpdir do |dir|
      key_path = "#{dir}/test_key"
      system("ssh-keygen -t ed25519 -f #{key_path} -N '' -q")

      config = Object.new
      config.define_singleton_method(:ssh_key) { nil }
      config.define_singleton_method(:[]=) { |_k, _v| nil }

      token_store = Object.new
      token_store.define_singleton_method(:on_info=) { |_cb| nil }
      token_store.define_singleton_method(:on_warning=) { |_cb| nil }
      token_store.define_singleton_method(:on_prompt_pub_key=) { |_cb| nil }
      token_store.define_singleton_method(:migrate_encryption) { |_o, _n| nil }

      yield dir, config, token_store, key_path
    end
  end

  def can_create_test_ssh_key?
    system('which ssh-keygen > /dev/null 2>&1')
  end
end
