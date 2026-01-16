# frozen_string_literal: true

require 'test_helper'

class TokenStoreTest < Minitest::Test
  def test_empty_returns_true_when_no_tokens
    with_temp_config do
      store = Slk::Services::TokenStore.new
      assert store.empty?
    end
  end

  def test_empty_returns_false_when_tokens_exist
    with_temp_config do |dir|
      write_tokens_file(dir, { 'myworkspace' => { 'token' => 'xoxb-test' } })
      store = Slk::Services::TokenStore.new
      refute store.empty?
    end
  end

  def test_workspace_names_returns_empty_array_when_no_tokens
    with_temp_config do
      store = Slk::Services::TokenStore.new
      assert_equal [], store.workspace_names
    end
  end

  def test_workspace_names_returns_all_names
    with_temp_config do |dir|
      write_tokens_file(dir, {
                          'workspace1' => { 'token' => 'xoxb-test1' },
                          'workspace2' => { 'token' => 'xoxb-test2' }
                        })
      store = Slk::Services::TokenStore.new
      assert_equal %w[workspace1 workspace2].sort, store.workspace_names.sort
    end
  end

  def test_exists_returns_false_for_unknown_workspace
    with_temp_config do
      store = Slk::Services::TokenStore.new
      refute store.exists?('nonexistent')
    end
  end

  def test_exists_returns_true_for_known_workspace
    with_temp_config do |dir|
      write_tokens_file(dir, { 'myworkspace' => { 'token' => 'xoxb-test' } })
      store = Slk::Services::TokenStore.new
      assert store.exists?('myworkspace')
    end
  end

  def test_workspace_raises_for_unknown_workspace
    with_temp_config do
      store = Slk::Services::TokenStore.new
      error = assert_raises(Slk::WorkspaceNotFoundError) do
        store.workspace('nonexistent')
      end
      assert_equal "Workspace 'nonexistent' not found", error.message
    end
  end

  def test_workspace_returns_workspace_model
    with_temp_config do |dir|
      write_tokens_file(dir, { 'myworkspace' => { 'token' => 'xoxb-test-token' } })
      store = Slk::Services::TokenStore.new
      workspace = store.workspace('myworkspace')

      assert_kind_of Slk::Models::Workspace, workspace
      assert_equal 'myworkspace', workspace.name
      assert_equal 'xoxb-test-token', workspace.token
    end
  end

  def test_workspace_returns_workspace_with_cookie
    with_temp_config do |dir|
      write_tokens_file(dir, {
                          'myworkspace' => { 'token' => 'xoxc-test-token', 'cookie' => 'xoxd-cookie' }
                        })
      store = Slk::Services::TokenStore.new
      workspace = store.workspace('myworkspace')

      assert_equal 'xoxc-test-token', workspace.token
      assert_equal 'xoxd-cookie', workspace.cookie
    end
  end

  def test_all_workspaces_returns_empty_array_when_no_tokens
    with_temp_config do
      store = Slk::Services::TokenStore.new
      assert_equal [], store.all_workspaces
    end
  end

  def test_all_workspaces_returns_workspace_models
    with_temp_config do |dir|
      write_tokens_file(dir, {
                          'ws1' => { 'token' => 'xoxb-test1' },
                          'ws2' => { 'token' => 'xoxb-test2' }
                        })
      store = Slk::Services::TokenStore.new
      workspaces = store.all_workspaces

      assert_equal 2, workspaces.size
      assert(workspaces.all? { |ws| ws.is_a?(Slk::Models::Workspace) })
      assert_equal %w[ws1 ws2].sort, workspaces.map(&:name).sort
    end
  end

  def test_add_creates_new_workspace
    with_temp_config do
      store = Slk::Services::TokenStore.new
      store.add('newworkspace', 'xoxb-new-token')

      assert store.exists?('newworkspace')
      workspace = store.workspace('newworkspace')
      assert_equal 'xoxb-new-token', workspace.token
    end
  end

  def test_add_with_cookie_stores_cookie
    with_temp_config do
      store = Slk::Services::TokenStore.new
      store.add('newworkspace', 'xoxc-new-token', 'xoxd-cookie')

      workspace = store.workspace('newworkspace')
      assert_equal 'xoxc-new-token', workspace.token
      assert_equal 'xoxd-cookie', workspace.cookie
    end
  end

  def test_add_persists_to_file
    with_temp_config do
      store = Slk::Services::TokenStore.new
      store.add('newworkspace', 'xoxb-new-token')

      # Create new store instance and verify data persisted
      new_store = Slk::Services::TokenStore.new
      assert new_store.exists?('newworkspace')
    end
  end

  def test_remove_returns_true_when_workspace_existed
    with_temp_config do |dir|
      write_tokens_file(dir, { 'myworkspace' => { 'token' => 'xoxb-test' } })
      store = Slk::Services::TokenStore.new

      result = store.remove('myworkspace')

      assert result
      refute store.exists?('myworkspace')
    end
  end

  def test_remove_returns_false_when_workspace_not_found
    with_temp_config do
      store = Slk::Services::TokenStore.new
      result = store.remove('nonexistent')
      refute result
    end
  end

  def test_remove_persists_change
    with_temp_config do |dir|
      write_tokens_file(dir, { 'myworkspace' => { 'token' => 'xoxb-test' } })
      store = Slk::Services::TokenStore.new
      store.remove('myworkspace')

      # Create new store instance and verify removal persisted
      new_store = Slk::Services::TokenStore.new
      refute new_store.exists?('myworkspace')
    end
  end

  # Corruption handling tests
  def test_corrupted_tokens_file_raises_error
    with_temp_config do |dir|
      config_dir = "#{dir}/slk"
      FileUtils.mkdir_p(config_dir)
      File.write("#{config_dir}/tokens.json", 'not valid json{')

      store = Slk::Services::TokenStore.new

      error = assert_raises(Slk::TokenStoreError) do
        store.empty?
      end

      assert_match(/corrupted/, error.message)
    end
  end

  def test_on_warning_callback_is_settable
    store = Slk::Services::TokenStore.new
    callback = ->(msg) { puts msg }
    store.on_warning = callback
    assert_equal callback, store.on_warning
  end

  def test_on_info_callback_is_settable
    store = Slk::Services::TokenStore.new
    callback = ->(msg) { puts msg }
    store.on_info = callback
    assert_equal callback, store.on_info
  end

  # migrate_encryption tests
  def test_migrate_encryption_does_nothing_when_keys_are_same
    with_temp_config do |dir|
      write_tokens_file(dir, { 'myworkspace' => { 'token' => 'xoxb-test' } })
      store = Slk::Services::TokenStore.new

      # Should not raise or change anything
      store.migrate_encryption('/same/key', '/same/key')

      assert store.exists?('myworkspace')
    end
  end

  def test_migrate_encryption_does_nothing_when_no_tokens
    with_temp_config do
      store = Slk::Services::TokenStore.new

      # Should not raise when there are no tokens to migrate
      store.migrate_encryption(nil, '/some/new/key.pub')
    end
  end

  def test_migrate_encryption_validates_new_key_type
    with_temp_config do |dir|
      write_tokens_file(dir, { 'myworkspace' => { 'token' => 'xoxb-test' } })

      # Create an ECDSA key (unsupported by age)
      key_path = "#{dir}/ecdsa_key"
      File.write(key_path, 'dummy private key')
      File.write("#{key_path}.pub", 'ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTI... user@host')

      store = Slk::Services::TokenStore.new

      error = assert_raises(Slk::EncryptionError) do
        store.migrate_encryption(nil, key_path)
      end

      assert_match(/Unsupported SSH key type/, error.message)
    end
  end

  def test_migrate_encryption_notifies_when_encrypting
    skip unless can_create_test_ssh_key?
    skip unless age_available?

    with_temp_config do |dir|
      write_tokens_file(dir, { 'myworkspace' => { 'token' => 'xoxb-test' } })

      # Create a valid ed25519 key
      key_path = "#{dir}/test_key"
      system("ssh-keygen -t ed25519 -f #{key_path} -N '' -q")

      store = Slk::Services::TokenStore.new
      messages = []
      store.on_info = ->(msg) { messages << msg }

      store.migrate_encryption(nil, key_path)

      assert_includes messages, 'Tokens have been encrypted with the new SSH key.'
    end
  end

  def test_migrate_encryption_notifies_when_decrypting_to_plaintext
    skip unless can_create_test_ssh_key?
    skip unless age_available?

    with_temp_config do |dir|
      # Create a valid ed25519 key
      key_path = "#{dir}/test_key"
      system("ssh-keygen -t ed25519 -f #{key_path} -N '' -q")

      # Write plaintext tokens first
      write_tokens_file(dir, { 'myworkspace' => { 'token' => 'xoxb-test' } })

      store = Slk::Services::TokenStore.new
      # Encrypt tokens first
      store.migrate_encryption(nil, key_path)

      # Now decrypt them
      messages = []
      store.on_warning = ->(msg) { messages << msg }
      store.migrate_encryption(key_path, nil)

      assert_includes messages, 'Tokens are now stored in plaintext.'
    end
  end

  def test_migrate_encryption_from_plaintext_to_encrypted
    skip unless can_create_test_ssh_key?
    skip unless age_available?

    with_temp_config do |dir|
      write_tokens_file(dir, { 'myworkspace' => { 'token' => 'xoxb-test' } })

      # Create a valid ed25519 key
      key_path = "#{dir}/test_key"
      system("ssh-keygen -t ed25519 -f #{key_path} -N '' -q")

      store = Slk::Services::TokenStore.new
      store.migrate_encryption(nil, key_path)

      config_dir = "#{dir}/slk"

      # Plain file should be removed
      refute File.exist?("#{config_dir}/tokens.json")
      # Encrypted file should exist
      assert File.exist?("#{config_dir}/tokens.age")
    end
  end

  def test_migrate_encryption_from_encrypted_to_plaintext
    skip unless can_create_test_ssh_key?
    skip unless age_available?

    with_temp_config do |dir|
      # Create a valid ed25519 key
      key_path = "#{dir}/test_key"
      system("ssh-keygen -t ed25519 -f #{key_path} -N '' -q")

      # Write plaintext tokens first, then encrypt
      write_tokens_file(dir, { 'myworkspace' => { 'token' => 'xoxb-test' } })
      store = Slk::Services::TokenStore.new
      store.migrate_encryption(nil, key_path)

      config_dir = "#{dir}/slk"
      assert File.exist?("#{config_dir}/tokens.age")

      # Now decrypt to plaintext
      store.migrate_encryption(key_path, nil)

      # Encrypted file should be removed
      refute File.exist?("#{config_dir}/tokens.age")
      # Plain file should exist
      assert File.exist?("#{config_dir}/tokens.json")

      # Verify tokens are readable
      tokens = JSON.parse(File.read("#{config_dir}/tokens.json"))
      assert_equal 'xoxb-test', tokens['myworkspace']['token']
    end
  end

  def test_migrate_encryption_from_key_to_different_key
    skip unless can_create_test_ssh_key?
    skip unless age_available?

    with_temp_config do |dir|
      # Create two different ed25519 keys
      key1_path = "#{dir}/test_key1"
      key2_path = "#{dir}/test_key2"
      system("ssh-keygen -t ed25519 -f #{key1_path} -N '' -q")
      system("ssh-keygen -t ed25519 -f #{key2_path} -N '' -q")

      # Write plaintext tokens first, then encrypt with key1
      write_tokens_file(dir, { 'myworkspace' => { 'token' => 'xoxb-secret-token' } })
      store = Slk::Services::TokenStore.new
      store.migrate_encryption(nil, key1_path)

      config_dir = "#{dir}/slk"
      encrypted_file = "#{config_dir}/tokens.age"
      assert File.exist?(encrypted_file)

      # Read original encrypted content for comparison
      original_encrypted = File.read(encrypted_file)

      # Now migrate from key1 to key2
      messages = []
      store.on_info = ->(msg) { messages << msg }
      store.migrate_encryption(key1_path, key2_path)

      # Encrypted file should still exist
      assert File.exist?(encrypted_file)

      # Content should be different (re-encrypted with new key)
      new_encrypted = File.read(encrypted_file)
      refute_equal original_encrypted, new_encrypted, 'File should be re-encrypted with new key'

      # Verify we can decrypt with key2 and get original content
      encryption = Slk::Services::Encryption.new
      decrypted = encryption.decrypt(encrypted_file, key2_path)
      tokens = JSON.parse(decrypted)
      assert_equal 'xoxb-secret-token', tokens['myworkspace']['token']

      # Verify we cannot decrypt with key1 anymore
      assert_raises(Slk::EncryptionError) do
        encryption.decrypt(encrypted_file, key1_path)
      end

      # Should have notified about re-encryption
      assert_includes messages, 'Tokens have been re-encrypted with the new SSH key.'
    end
  end

  # File permissions test
  def test_add_creates_file_with_restricted_permissions
    skip 'File permissions not applicable on Windows' if Gem.win_platform?

    with_temp_config do |dir|
      store = Slk::Services::TokenStore.new
      store.add('testws', 'xoxb-test')

      config_dir = "#{dir}/slk"
      tokens_file = "#{config_dir}/tokens.json"

      assert File.exist?(tokens_file)
      # Check file mode (0600 = owner read/write only)
      mode = File.stat(tokens_file).mode & 0o777
      assert_equal 0o600, mode
    end
  end

  # Validation tests
  def test_add_validates_token_format
    with_temp_config do
      store = Slk::Services::TokenStore.new

      error = assert_raises(ArgumentError) do
        store.add('testws', 'invalid-token')
      end

      assert_match(/invalid token format/, error.message)
    end
  end

  def test_add_validates_name_not_empty
    with_temp_config do
      store = Slk::Services::TokenStore.new

      error = assert_raises(ArgumentError) do
        store.add('', 'xoxb-test')
      end

      assert_match(/name cannot be empty/, error.message)
    end
  end

  def test_add_validates_xoxc_requires_cookie
    with_temp_config do
      store = Slk::Services::TokenStore.new

      error = assert_raises(ArgumentError) do
        store.add('testws', 'xoxc-test')
      end

      assert_match(/require a cookie/, error.message)
    end
  end

  private

  def write_tokens_file(dir, tokens)
    config_dir = "#{dir}/slk"
    FileUtils.mkdir_p(config_dir)
    File.write("#{config_dir}/tokens.json", JSON.generate(tokens))
  end

  def can_create_test_ssh_key?
    require 'open3'
    _, _, status = Open3.capture3('ssh-keygen', '-V')
    status.success?
  rescue Errno::ENOENT
    false
  end

  def age_available?
    require 'open3'
    _, _, status = Open3.capture3('age', '--version')
    status.success?
  rescue Errno::ENOENT
    false
  end
end
