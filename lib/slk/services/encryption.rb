# frozen_string_literal: true

require 'open3'

module Slk
  module Services
    # Encrypts/decrypts tokens using age with SSH keys
    class Encryption
      def available?
        system('which age > /dev/null 2>&1')
      end

      def encrypt(content, ssh_key_path, output_file) # rubocop:disable Naming/PredicateMethod
        raise EncryptionError, 'age encryption tool not available' unless available?

        public_key = "#{ssh_key_path}.pub"
        raise EncryptionError, "Public key not found: #{public_key}" unless File.exist?(public_key)

        _output, error, status = Open3.capture3('age', '-R', public_key, '-o', output_file, stdin_data: content)

        raise EncryptionError, "Failed to encrypt: #{error.strip}" unless status.success?

        true
      end

      # Decrypt an age-encrypted file using an SSH key
      # @param encrypted_file [String] Path to the encrypted file
      # @param ssh_key_path [String] Path to the SSH private key
      # @return [String, nil] Decrypted content, or nil if file doesn't exist
      # @raise [EncryptionError] If age tool not available, key not found, or decryption fails
      def decrypt(encrypted_file, ssh_key_path)
        # File not existing is not an error - it just means no encrypted data yet
        return nil unless File.exist?(encrypted_file)

        raise EncryptionError, 'age encryption tool not available' unless available?
        raise EncryptionError, "SSH key not found: #{ssh_key_path}" unless File.exist?(ssh_key_path)

        output, error, status = Open3.capture3('age', '-d', '-i', ssh_key_path, encrypted_file)

        raise EncryptionError, "Failed to decrypt #{encrypted_file}: #{error.strip}" unless status.success?

        output
      rescue Errno::ENOENT => e
        raise EncryptionError, "Decryption failed: #{e.message}"
      end
    end
  end
end
