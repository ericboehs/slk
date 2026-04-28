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
    token_store = mock_token_store(migrate_encryption: ->(_o, _n, _ctx) { raise Slk::EncryptionError, 'Key invalid' })

    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)

    result = manager.set('/path/to/key')

    refute result[:success]
    assert_equal 'Key invalid', result[:error]
  end

  def test_set_returns_error_on_file_not_found
    config = mock_config
    token_store = mock_token_store(migrate_encryption: ->(_o, _n, _ctx) { raise Errno::ENOENT, 'No such file' })

    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)

    result = manager.set('/path/to/key')

    refute result[:success]
    assert_match(/File not found/, result[:error])
  end

  def test_set_returns_error_on_permission_denied
    config = mock_config
    token_store = mock_token_store(migrate_encryption: ->(_o, _n, _ctx) { raise Errno::EACCES, 'Permission denied' })

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
    token_store = mock_token_store(migrate_encryption: lambda { |_o, _n, _ctx|
      raise Slk::EncryptionError, 'Decrypt failed'
    })

    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)

    result = manager.unset

    refute result[:success]
    assert_equal 'Decrypt failed', result[:error]
  end

  def test_on_info_callback_is_propagated
    info_messages = []

    config = mock_config
    token_store = mock_token_store(
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

  def test_unset_with_no_old_key_and_no_encrypted_tokens
    config = mock_config(ssh_key: nil)
    token_store = mock_token_store

    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)
    with_temp_config do
      result = manager.unset
      assert result[:success]
    end
  end

  def test_unset_prompts_when_old_key_unknown_and_tokens_exist
    config = mock_config(ssh_key: nil)
    token_store = mock_token_store

    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)
    with_temp_config do |dir|
      tokens_age_path = "#{dir}/slk/tokens.age"
      FileUtils.mkdir_p(File.dirname(tokens_age_path))
      File.write(tokens_age_path, 'encrypted')

      $stdin = StringIO.new("/some/path/to/key\n")
      result = manager.unset
      assert result[:success]
    ensure
      $stdin = STDIN
    end
  end

  def test_unset_cancels_when_no_path_provided
    config = mock_config(ssh_key: nil)
    token_store = mock_token_store

    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)
    with_temp_config do |dir|
      tokens_age_path = "#{dir}/slk/tokens.age"
      FileUtils.mkdir_p(File.dirname(tokens_age_path))
      File.write(tokens_age_path, 'encrypted')

      $stdin = StringIO.new("\n")
      result = manager.unset
      refute result[:success]
      assert_match(/cancelled/i, result[:error])
    ensure
      $stdin = STDIN
    end
  end

  def test_set_returns_error_on_disk_full
    config = mock_config
    token_store = mock_token_store(migrate_encryption: ->(_o, _n, _ctx) { raise Errno::ENOSPC, 'No space' })

    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)
    result = manager.set('/path/to/key')
    refute result[:success]
    assert_match(/Disk full/, result[:error])
  end

  def test_set_returns_error_on_invalid_argument
    config = mock_config
    token_store = mock_token_store(migrate_encryption: ->(_o, _n, _ctx) { raise ArgumentError, 'bad arg' })

    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)
    result = manager.set('/path/to/key')
    refute result[:success]
    assert_match(/Invalid path: bad arg/, result[:error])
  end

  def test_prompt_pub_key_callback_returns_path
    captured_path = nil
    config = mock_config
    token_store = mock_token_store(migrate_encryption: lambda { |_o, _n, ctx|
      cb = ctx[:on_prompt_pub_key]
      captured_path = cb&.call('/private/key') if cb
    })

    Tempfile.create(['key', '.pub']) do |tf|
      manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)
      $stdin = StringIO.new("#{tf.path}\n")
      manager.set('/path/to/key')
      assert_equal File.expand_path(tf.path), captured_path
    ensure
      $stdin = STDIN
    end
  end

  def test_prompt_pub_key_callback_cancels
    captured_path = :unchanged
    config = mock_config
    token_store = mock_token_store(migrate_encryption: lambda { |_o, _n, ctx|
      cb = ctx[:on_prompt_pub_key]
      captured_path = cb&.call('/private/key') if cb
    })

    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)
    $stdin = StringIO.new("\n")
    manager.set('/path/to/key')
    assert_nil captured_path
  ensure
    $stdin = STDIN
  end

  def test_set_returns_error_on_eperm
    config = mock_config
    token_store = mock_token_store(migrate_encryption: ->(_o, _n, _ctx) { raise Errno::EPERM, 'denied' })

    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)
    result = manager.set('/path/to/key')
    refute result[:success]
    assert_match(/Permission denied/, result[:error])
  end

  def test_set_returns_error_on_read_only_fs
    config = mock_config
    token_store = mock_token_store(migrate_encryption: ->(_o, _n, _ctx) { raise Errno::EROFS, 'ro' })

    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)
    result = manager.set('/path/to/key')
    refute result[:success]
    assert_match(/Read-only/, result[:error])
  end

  def test_unset_prompt_uses_existing_old_key
    config = mock_config(ssh_key: '/old/key')
    token_store = mock_token_store
    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)
    result = manager.unset
    assert result[:success]
  end

  def test_unset_with_eof_stdin_raises_encryption_error
    config = mock_config(ssh_key: nil)
    token_store = mock_token_store

    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)
    with_temp_config do |dir|
      tokens_age_path = "#{dir}/slk/tokens.age"
      FileUtils.mkdir_p(File.dirname(tokens_age_path))
      File.write(tokens_age_path, 'encrypted')

      $stdin = StringIO.new('')
      result = manager.unset
      refute result[:success]
    ensure
      $stdin = STDIN
    end
  end

  def test_prompt_pub_key_callback_eof
    captured_path = :unchanged
    config = mock_config
    token_store = mock_token_store(migrate_encryption: lambda { |_o, _n, ctx|
      cb = ctx[:on_prompt_pub_key]
      captured_path = cb&.call('/private/key') if cb
    })

    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)
    $stdin = StringIO.new('')
    manager.set('/path/to/key')
    assert_nil captured_path
  ensure
    $stdin = STDIN
  end

  def test_info_callback_no_op_when_on_info_not_set
    # Exercises the @on_info&.call branch when @on_info is nil
    config = mock_config
    token_store = mock_token_store(
      migrate_encryption: ->(_o, _n, ctx) { ctx[:on_info]&.call('hi') }
    )
    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)
    # No on_info= set on manager
    result = manager.set('/path/to/key')
    assert result[:success]
  end

  def test_warning_callback_no_op_when_on_warning_not_set
    config = mock_config
    token_store = mock_token_store(
      migrate_encryption: ->(_o, _n, ctx) { ctx[:on_warning]&.call('warn') }
    )
    manager = Slk::Commands::SshKeyManager.new(config: config, token_store: token_store, output: @output)
    result = manager.set('/path/to/key')
    assert result[:success]
  end

  private

  def mock_config(ssh_key: nil, on_set: nil)
    Object.new.tap do |config|
      config.define_singleton_method(:ssh_key) { ssh_key }
      config.define_singleton_method(:[]=) { |k, v| on_set&.call(k, v) }
    end
  end

  def mock_token_store(migrate_encryption: nil)
    ctx = {}
    Object.new.tap do |store|
      store.define_singleton_method(:on_info=) { |cb| ctx[:on_info] = cb }
      store.define_singleton_method(:on_warning=) { |cb| ctx[:on_warning] = cb }
      store.define_singleton_method(:on_prompt_pub_key=) { |cb| ctx[:on_prompt_pub_key] = cb }
      store.define_singleton_method(:migrate_encryption) do |o, n|
        migrate_encryption&.call(o, n, ctx)
      end
    end
  end

  def can_create_test_ssh_key?
    require 'open3'
    Open3.capture3('ssh-keygen', '-?')
    true
  rescue Errno::ENOENT
    false
  end
end
