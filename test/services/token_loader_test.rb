# frozen_string_literal: true

require 'test_helper'

class TokenLoaderTest < Minitest::Test
  def setup
    @encryption = Slk::Services::Encryption.new
  end

  # load tests
  def test_load_returns_empty_hash_when_no_files_exist
    Dir.mktmpdir do |dir|
      paths = mock_paths(dir)
      loader = Slk::Services::TokenLoader.new(encryption: @encryption, paths: paths)

      result = loader.load('/path/to/key')
      assert_equal({}, result)
    end
  end

  def test_load_raises_when_encrypted_exists_without_ssh_key
    Dir.mktmpdir do |dir|
      paths = mock_paths(dir)
      loader = Slk::Services::TokenLoader.new(encryption: @encryption, paths: paths)
      File.write(File.join(dir, 'tokens.age'), 'encrypted')

      error = assert_raises(Slk::EncryptionError) do
        loader.load(nil)
      end

      assert_match(/Cannot read encrypted tokens without SSH key/, error.message)
    end
  end

  def test_load_parses_plain_file_when_no_encrypted_exists
    Dir.mktmpdir do |dir|
      paths = mock_paths(dir)
      loader = Slk::Services::TokenLoader.new(encryption: @encryption, paths: paths)
      File.write(File.join(dir, 'tokens.json'), '{"workspace": "token123"}')

      result = loader.load(nil)
      assert_equal({ 'workspace' => 'token123' }, result)
    end
  end

  def test_load_raises_on_corrupted_plain_file
    Dir.mktmpdir do |dir|
      paths = mock_paths(dir)
      loader = Slk::Services::TokenLoader.new(encryption: @encryption, paths: paths)
      File.write(File.join(dir, 'tokens.json'), 'not valid json{')

      error = assert_raises(Slk::TokenStoreError) do
        loader.load(nil)
      end

      assert_match(/corrupted/, error.message)
    end
  end

  def test_load_raises_when_plain_file_disappears
    Dir.mktmpdir do |dir|
      paths = mock_paths(dir)
      loader = Slk::Services::TokenLoader.new(encryption: @encryption, paths: paths)
      tokens_file = File.join(dir, 'tokens.json')
      File.write(tokens_file, '{}')

      # Make the file exist for the check but not for reading
      loader.define_singleton_method(:plain_file_exists?) { true }
      File.delete(tokens_file)

      error = assert_raises(Slk::TokenStoreError) do
        loader.send(:parse_plain_file)
      end

      assert_match(/disappeared unexpectedly/, error.message)
    end
  end

  # load_auto tests
  def test_load_auto_returns_empty_hash_when_no_files
    Dir.mktmpdir do |dir|
      paths = mock_paths(dir)
      loader = Slk::Services::TokenLoader.new(encryption: @encryption, paths: paths)
      config = mock_config(ssh_key: nil)

      result = loader.load_auto(config)
      assert_equal({}, result)
    end
  end

  def test_load_auto_loads_plain_file_when_no_encrypted
    Dir.mktmpdir do |dir|
      paths = mock_paths(dir)
      loader = Slk::Services::TokenLoader.new(encryption: @encryption, paths: paths)
      config = mock_config(ssh_key: nil)
      File.write(File.join(dir, 'tokens.json'), '{"workspace": "token456"}')

      result = loader.load_auto(config)
      assert_equal({ 'workspace' => 'token456' }, result)
    end
  end

  def test_load_auto_raises_when_encrypted_exists_without_config_ssh_key
    Dir.mktmpdir do |dir|
      paths = mock_paths(dir)
      loader = Slk::Services::TokenLoader.new(encryption: @encryption, paths: paths)
      config = mock_config(ssh_key: nil)
      File.write(File.join(dir, 'tokens.age'), 'encrypted')

      error = assert_raises(Slk::EncryptionError) do
        loader.load_auto(config)
      end

      assert_match(/no SSH key configured/, error.message)
    end
  end

  # encrypted_file_exists? / plain_file_exists? tests
  def test_encrypted_file_exists_returns_true_when_file_present
    Dir.mktmpdir do |dir|
      paths = mock_paths(dir)
      loader = Slk::Services::TokenLoader.new(encryption: @encryption, paths: paths)
      File.write(File.join(dir, 'tokens.age'), 'content')

      assert loader.encrypted_file_exists?
    end
  end

  def test_encrypted_file_exists_returns_false_when_not_present
    Dir.mktmpdir do |dir|
      paths = mock_paths(dir)
      loader = Slk::Services::TokenLoader.new(encryption: @encryption, paths: paths)

      refute loader.encrypted_file_exists?
    end
  end

  def test_plain_file_exists_returns_true_when_file_present
    Dir.mktmpdir do |dir|
      paths = mock_paths(dir)
      loader = Slk::Services::TokenLoader.new(encryption: @encryption, paths: paths)
      File.write(File.join(dir, 'tokens.json'), '{}')

      assert loader.plain_file_exists?
    end
  end

  # Integration test with real encryption (when age available)
  def test_load_decrypts_encrypted_file
    skip unless @encryption.available?
    skip unless can_create_test_ssh_key?

    Dir.mktmpdir do |dir|
      key_path = "#{dir}/test_key"
      system("ssh-keygen -t ed25519 -f #{key_path} -N '' -q")

      paths = mock_paths(dir)

      # Encrypt tokens file
      tokens = { 'workspace' => 'secret_token' }
      encrypted_file = File.join(dir, 'tokens.age')
      @encryption.encrypt(JSON.generate(tokens), key_path, encrypted_file)

      loader = Slk::Services::TokenLoader.new(encryption: @encryption, paths: paths)
      result = loader.load(key_path)

      assert_equal tokens, result
    end
  end

  def test_load_raises_on_corrupted_encrypted_file
    skip unless @encryption.available?
    skip unless can_create_test_ssh_key?

    Dir.mktmpdir do |dir|
      key_path = "#{dir}/test_key"
      system("ssh-keygen -t ed25519 -f #{key_path} -N '' -q")

      paths = mock_paths(dir)

      # Encrypt invalid JSON
      encrypted_file = File.join(dir, 'tokens.age')
      @encryption.encrypt('not valid json{', key_path, encrypted_file)

      loader = Slk::Services::TokenLoader.new(encryption: @encryption, paths: paths)

      error = assert_raises(Slk::TokenStoreError) do
        loader.load(key_path)
      end

      assert_match(/corrupted/, error.message)
    end
  end

  private

  def mock_paths(dir)
    Object.new.tap do |paths|
      paths.define_singleton_method(:config_file) { |f| File.join(dir, f) }
    end
  end

  def mock_config(ssh_key:)
    Object.new.tap do |config|
      config.define_singleton_method(:ssh_key) { ssh_key }
    end
  end

  def can_create_test_ssh_key?
    require 'open3'
    _, _, status = Open3.capture3('ssh-keygen', '-V')
    status.success?
  rescue Errno::ENOENT
    false
  end
end
