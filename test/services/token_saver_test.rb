# frozen_string_literal: true

require 'test_helper'

class TokenSaverTest < Minitest::Test
  def setup
    @encryption = Slk::Services::Encryption.new
  end

  # save tests
  def test_save_writes_plaintext_when_no_ssh_key
    Dir.mktmpdir do |dir|
      paths = mock_paths(dir)
      saver = Slk::Services::TokenSaver.new(encryption: @encryption, paths: paths)
      tokens = { 'workspace' => 'token123' }

      saver.save(tokens, nil)

      plain_file = File.join(dir, 'tokens.json')
      assert File.exist?(plain_file)
      assert_equal tokens, JSON.parse(File.read(plain_file))

      # Check file permissions (Unix only - Windows doesn't support chmod)
      unless Gem.win_platform?
        mode = File.stat(plain_file).mode & 0o777
        assert_equal 0o600, mode, 'Plain tokens file should have 600 permissions'
      end
    end
  end

  def test_save_with_cleanup_removes_other_format
    Dir.mktmpdir do |dir|
      paths = mock_paths(dir)

      # Create encrypted file first
      encrypted_file = File.join(dir, 'tokens.age')
      File.write(encrypted_file, 'old encrypted')

      saver = Slk::Services::TokenSaver.new(encryption: @encryption, paths: paths)
      tokens = { 'workspace' => 'token123' }

      saver.save_with_cleanup(tokens, nil)

      # Plain file should exist
      plain_file = File.join(dir, 'tokens.json')
      assert File.exist?(plain_file)

      # Encrypted file should be removed
      refute File.exist?(encrypted_file)
    end
  end

  def test_save_raises_on_write_failure
    skip 'chmod does not prevent writes on Windows' if Gem.win_platform?

    Dir.mktmpdir do |dir|
      paths = mock_paths(dir)

      # Make directory read-only to force write failure
      File.chmod(0o555, dir)

      saver = Slk::Services::TokenSaver.new(encryption: @encryption, paths: paths)

      error = assert_raises(Slk::TokenStoreError) do
        saver.save({ 'test' => 'token' }, nil)
      end

      assert_match(/Failed to save tokens/, error.message)
    ensure
      File.chmod(0o755, dir)
    end
  end

  def test_save_uses_atomic_writes
    Dir.mktmpdir do |dir|
      paths = mock_paths(dir)

      # Write initial tokens
      plain_file = File.join(dir, 'tokens.json')
      File.write(plain_file, '{"old": "data"}')

      saver = Slk::Services::TokenSaver.new(encryption: @encryption, paths: paths)
      tokens = { 'workspace' => 'newtoken' }

      saver.save(tokens, nil)

      # Verify file was updated
      assert_equal tokens, JSON.parse(File.read(plain_file))

      # Verify no temp file left behind
      refute File.exist?("#{plain_file}.tmp")
    end
  end

  # Integration test with encryption
  def test_save_encrypts_when_ssh_key_provided
    skip unless @encryption.available?
    skip unless can_create_test_ssh_key?

    Dir.mktmpdir do |dir|
      key_path = "#{dir}/test_key"
      system("ssh-keygen -t ed25519 -f #{key_path} -N '' -q")

      paths = mock_paths(dir)
      saver = Slk::Services::TokenSaver.new(encryption: @encryption, paths: paths)
      tokens = { 'workspace' => 'secret_token' }

      saver.save(tokens, key_path)

      encrypted_file = File.join(dir, 'tokens.age')
      plain_file = File.join(dir, 'tokens.json')

      # Encrypted file should exist
      assert File.exist?(encrypted_file)

      # Plain file should be removed
      refute File.exist?(plain_file)

      # Verify we can decrypt and get original content
      decrypted = @encryption.decrypt(encrypted_file, key_path)
      assert_equal tokens, JSON.parse(decrypted)
    end
  end

  def test_save_encrypted_removes_temp_on_failure
    skip unless @encryption.available?

    Dir.mktmpdir do |dir|
      paths = mock_paths(dir)

      # Create a fake encryption that fails with EncryptionError
      failing_encryption = Object.new
      failing_encryption.define_singleton_method(:encrypt) { |_c, _k, _o| raise Slk::EncryptionError, 'Encryption failed' }

      saver = Slk::Services::TokenSaver.new(encryption: failing_encryption, paths: paths)

      assert_raises(Slk::TokenStoreError) do
        saver.save({ 'test' => 'token' }, '/path/to/key')
      end

      # Verify no temp file left behind
      temp_file = File.join(dir, 'tokens.age.tmp')
      refute File.exist?(temp_file)
    end
  end

  def test_save_with_cleanup_removes_plain_when_encrypting
    skip unless @encryption.available?
    skip unless can_create_test_ssh_key?

    Dir.mktmpdir do |dir|
      key_path = "#{dir}/test_key"
      system("ssh-keygen -t ed25519 -f #{key_path} -N '' -q")

      paths = mock_paths(dir)

      # Create plain file first
      plain_file = File.join(dir, 'tokens.json')
      File.write(plain_file, '{"old": "plain_token"}')

      saver = Slk::Services::TokenSaver.new(encryption: @encryption, paths: paths)
      tokens = { 'workspace' => 'new_secret' }

      saver.save_with_cleanup(tokens, key_path)

      encrypted_file = File.join(dir, 'tokens.age')
      assert File.exist?(encrypted_file)
      refute File.exist?(plain_file)
    end
  end

  private

  def mock_paths(dir)
    Object.new.tap do |paths|
      paths.define_singleton_method(:config_file) { |f| File.join(dir, f) }
      paths.define_singleton_method(:ensure_config_dir) { FileUtils.mkdir_p(dir) }
    end
  end

  def can_create_test_ssh_key?
    system('which ssh-keygen > /dev/null 2>&1')
  end
end
