# frozen_string_literal: true

require 'test_helper'

class EncryptionTest < Minitest::Test
  def setup
    @encryption = Slk::Services::Encryption.new
  end

  # available? tests
  def test_available_returns_boolean
    result = @encryption.available?
    assert [true, false].include?(result)
  end

  # validate_key_type! tests
  def test_validate_key_type_accepts_ed25519
    Dir.mktmpdir do |dir|
      key_path = "#{dir}/test_key"
      File.write(key_path, 'dummy private key')
      File.write("#{key_path}.pub", 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@host')

      assert @encryption.validate_key_type!(key_path)
    end
  end

  def test_validate_key_type_accepts_rsa
    Dir.mktmpdir do |dir|
      key_path = "#{dir}/test_key"
      File.write(key_path, 'dummy private key')
      File.write("#{key_path}.pub", 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAB... user@host')

      assert @encryption.validate_key_type!(key_path)
    end
  end

  def test_validate_key_type_rejects_ecdsa
    Dir.mktmpdir do |dir|
      key_path = "#{dir}/test_key"
      File.write(key_path, 'dummy private key')
      File.write("#{key_path}.pub", 'ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTI... user@host')

      error = assert_raises(Slk::EncryptionError) do
        @encryption.validate_key_type!(key_path)
      end

      assert_match(/Unsupported SSH key type: ecdsa-sha2-nistp256/, error.message)
      assert_match(/age only supports: ssh-rsa, ssh-ed25519/, error.message)
    end
  end

  def test_validate_key_type_raises_when_private_key_missing
    Dir.mktmpdir do |dir|
      key_path = "#{dir}/nonexistent"

      error = assert_raises(Slk::EncryptionError) do
        @encryption.validate_key_type!(key_path)
      end

      assert_match(/Private key not found/, error.message)
    end
  end

  def test_validate_key_type_raises_when_public_key_missing
    Dir.mktmpdir do |dir|
      key_path = "#{dir}/test_key"
      File.write(key_path, 'dummy private key')
      # No .pub file created

      error = assert_raises(Slk::EncryptionError) do
        @encryption.validate_key_type!(key_path)
      end

      assert_match(/Public key not found/, error.message)
    end
  end

  def test_validate_key_type_prompts_for_pub_key_when_not_found
    Dir.mktmpdir do |dir|
      key_path = "#{dir}/test_key"
      alt_pub_path = "#{dir}/alt_key.pub"
      File.write(key_path, 'dummy private key')
      File.write(alt_pub_path, 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... user@host')

      @encryption.on_prompt_pub_key = ->(_path) { alt_pub_path }

      assert @encryption.validate_key_type!(key_path)
    end
  end

  def test_validate_key_type_rejects_empty_pub_file
    Dir.mktmpdir do |dir|
      key_path = "#{dir}/test_key"
      File.write(key_path, 'dummy private key')
      File.write("#{key_path}.pub", '')

      error = assert_raises(Slk::EncryptionError) do
        @encryption.validate_key_type!(key_path)
      end

      assert_match(/Unsupported SSH key type: unknown/, error.message)
    end
  end

  def test_validate_key_type_rejects_mismatched_key_pair
    skip unless can_create_test_ssh_key?

    Dir.mktmpdir do |dir|
      # Create two different key pairs
      key1_path = "#{dir}/key1"
      key2_path = "#{dir}/key2"
      system("ssh-keygen -t ed25519 -f #{key1_path} -N '' -q")
      system("ssh-keygen -t ed25519 -f #{key2_path} -N '' -q")

      # Use key1's private key with key2's public key
      File.write("#{key1_path}.pub", File.read("#{key2_path}.pub"))

      error = assert_raises(Slk::EncryptionError) do
        @encryption.validate_key_type!(key1_path)
      end

      assert_match(/Public key does not match private key/, error.message)
    end
  end

  def test_validate_key_type_accepts_matching_key_pair
    skip unless can_create_test_ssh_key?

    Dir.mktmpdir do |dir|
      key_path = "#{dir}/test_key"
      system("ssh-keygen -t ed25519 -f #{key_path} -N '' -q")

      assert @encryption.validate_key_type!(key_path)
    end
  end

  # encrypt tests
  def test_encrypt_raises_when_age_not_available
    encryption = Slk::Services::Encryption.new

    # Stub available? to return false
    encryption.define_singleton_method(:available?) { false }

    error = assert_raises(Slk::EncryptionError) do
      encryption.encrypt('test content', '/path/to/key', '/path/to/output')
    end

    assert_equal 'age encryption tool not available', error.message
  end

  def test_encrypt_raises_when_public_key_not_found
    skip unless @encryption.available?

    Dir.mktmpdir do |dir|
      key_path = "#{dir}/test_key"
      File.write(key_path, 'dummy private key')
      output_path = "#{dir}/output.age"

      error = assert_raises(Slk::EncryptionError) do
        @encryption.encrypt('test content', key_path, output_path)
      end

      assert_match(/Public key not found/, error.message)
    end
  end

  # decrypt tests
  def test_decrypt_raises_when_age_not_available_but_file_exists
    Dir.mktmpdir do |dir|
      encrypted_path = "#{dir}/tokens.age"
      File.write(encrypted_path, 'encrypted content')
      key_path = "#{dir}/key"
      File.write(key_path, 'dummy key')

      encryption = Slk::Services::Encryption.new
      encryption.define_singleton_method(:available?) { false }

      error = assert_raises(Slk::EncryptionError) do
        encryption.decrypt(encrypted_path, key_path)
      end

      assert_equal 'age encryption tool not available', error.message
    end
  end

  def test_decrypt_returns_nil_when_encrypted_file_not_found
    Dir.mktmpdir do |dir|
      encrypted_path = "#{dir}/nonexistent.age"
      key_path = "#{dir}/key"
      File.write(key_path, 'dummy key')

      result = @encryption.decrypt(encrypted_path, key_path)

      assert_nil result
    end
  end

  def test_decrypt_raises_when_ssh_key_not_found
    skip unless @encryption.available?

    Dir.mktmpdir do |dir|
      encrypted_path = "#{dir}/tokens.age"
      File.write(encrypted_path, 'dummy encrypted content')
      key_path = "#{dir}/nonexistent_key"

      error = assert_raises(Slk::EncryptionError) do
        @encryption.decrypt(encrypted_path, key_path)
      end

      assert_match(/SSH key not found/, error.message)
    end
  end

  # Integration test (only runs if age is available and test SSH keys exist)
  def test_encrypt_and_decrypt_roundtrip
    skip unless @encryption.available?
    skip unless can_create_test_ssh_key?

    Dir.mktmpdir do |dir|
      # Create a test SSH key pair using ssh-keygen
      key_path = "#{dir}/test_key"
      system("ssh-keygen -t ed25519 -f #{key_path} -N '' -q")

      encrypted_path = "#{dir}/test.age"
      original_content = 'Hello, World! This is secret content.'

      @encryption.encrypt(original_content, key_path, encrypted_path)

      assert File.exist?(encrypted_path), 'Encrypted file should be created'

      decrypted = @encryption.decrypt(encrypted_path, key_path)

      assert_equal original_content, decrypted
    end
  end

  private

  def can_create_test_ssh_key?
    system('which ssh-keygen > /dev/null 2>&1')
  end
end
