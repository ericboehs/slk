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

    Dir.mktmpdir do |dir|
      key_path = "#{dir}/test_key"
      system("ssh-keygen -t ed25519 -f #{key_path} -N '' -q")

      set_path = nil
      config = mock_config(ssh_key: nil, on_set: ->(k, v) { set_path = v if k == 'ssh_key' })
      token_store = mock_token_store

      manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)

      result = manager.set(key_path)

      assert result[:success]
      # Verify the path was stored (File.expand_path is called internally)
      assert set_path&.start_with?('/'), 'Path should be absolute'
    end
  end

  def test_set_rejects_pub_key_file
    config = mock_config
    token_store = mock_token_store
    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)

    result = manager.set('/path/to/key.pub')

    refute result[:success]
    assert_match(/private key path, not the public key/, result[:error])
  end

  def test_set_returns_error_on_encryption_error
    config = mock_config
    token_store = mock_token_store(migrate_encryption: ->(_o, _n) { raise Slk::EncryptionError, 'Key invalid' })

    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)

    result = manager.set('/path/to/key')

    refute result[:success]
    assert_equal 'Key invalid', result[:error]
  end

  def test_set_returns_error_on_file_not_found
    config = mock_config
    token_store = mock_token_store(migrate_encryption: ->(_o, _n) { raise Errno::ENOENT, 'No such file' })

    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)

    result = manager.set('/path/to/key')

    refute result[:success]
    assert_match(/File not found/, result[:error])
  end

  def test_set_returns_error_on_permission_denied
    config = mock_config
    token_store = mock_token_store(migrate_encryption: ->(_o, _n) { raise Errno::EACCES, 'Permission denied' })

    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)

    result = manager.set('/path/to/key')

    refute result[:success]
    assert_match(/Permission denied/, result[:error])
  end

  def test_set_returns_success_with_message
    config = mock_config
    token_store = mock_token_store

    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)

    result = manager.set('/path/to/key')

    assert result[:success]
    # On Windows, path gets expanded to D:/path/to/key
    assert_match(/Set ssh_key = .*path.to.key/, result[:message])
  end

  def test_unset_clears_ssh_key
    config = mock_config(ssh_key: '/old/key')
    token_store = mock_token_store

    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)

    result = manager.unset

    assert result[:success]
    assert_match(/Cleared ssh_key/, result[:message])
  end

  def test_unset_returns_error_on_encryption_error
    config = mock_config(ssh_key: '/old/key')
    token_store = mock_token_store(migrate_encryption: ->(_o, _n) { raise Slk::EncryptionError, 'Decrypt failed' })

    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)

    result = manager.unset

    refute result[:success]
    assert_equal 'Decrypt failed', result[:error]
  end

  def test_on_info_callback_is_propagated
    info_messages = []

    config = mock_config
    token_store = mock_token_store(
      capture_on_info: true,
      migrate_encryption: ->(_o, _n, ctx) { ctx[:on_info]&.call('Migration info') }
    )

    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)
    manager.on_info = ->(msg) { info_messages << msg }

    manager.set('/path/to/key')

    assert_includes info_messages, 'Migration info'
  end

  def test_on_warning_callback_is_propagated
    warning_messages = []

    config = mock_config
    token_store = mock_token_store(
      capture_on_warning: true,
      migrate_encryption: ->(_o, _n, ctx) { ctx[:on_warning]&.call('Migration warning') }
    )

    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)
    manager.on_warning = ->(msg) { warning_messages << msg }

    manager.set('/path/to/key')

    assert_includes warning_messages, 'Migration warning'
  end

  def test_set_clears_key_on_empty_string
    cleared = false
    config = mock_config(on_set: ->(k, v) { cleared = true if k == 'ssh_key' && v.nil? })
    token_store = mock_token_store

    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)

    result = manager.set('')

    assert result[:success]
    assert cleared, 'Config ssh_key should be set to nil'
  end

  private

  def mock_config(ssh_key: nil, on_set: nil)
    Object.new.tap do |config|
      config.define_singleton_method(:ssh_key) { ssh_key }
      config.define_singleton_method(:[]=) { |k, v| on_set&.call(k, v) }
    end
  end

  def mock_token_store(migrate_encryption: nil, capture_on_info: false, capture_on_warning: false)
    Object.new.tap do |store|
      ctx = {}

      if capture_on_info
        store.define_singleton_method(:on_info=) { |cb| ctx[:on_info] = cb }
      else
        store.define_singleton_method(:on_info=) { |_cb| nil }
      end

      if capture_on_warning
        store.define_singleton_method(:on_warning=) { |cb| ctx[:on_warning] = cb }
      else
        store.define_singleton_method(:on_warning=) { |_cb| nil }
      end

      store.define_singleton_method(:on_prompt_pub_key=) { |_cb| nil }

      if migrate_encryption
        if migrate_encryption.arity == 3
          store.define_singleton_method(:migrate_encryption) { |o, n| migrate_encryption.call(o, n, ctx) }
        else
          store.define_singleton_method(:migrate_encryption) { |o, n| migrate_encryption.call(o, n) }
        end
      else
        store.define_singleton_method(:migrate_encryption) { |_o, _n| nil }
      end
    end
  end

  def can_create_test_ssh_key?
    system('which ssh-keygen > /dev/null 2>&1')
  end
end
