# frozen_string_literal: true

require 'open3'

module Slk
  module Services
    # Encrypts/decrypts tokens using age with SSH keys
    class Encryption
      SUPPORTED_KEY_TYPES = %w[ssh-rsa ssh-ed25519].freeze

      attr_accessor :on_prompt_pub_key

      def available?
        system('which age > /dev/null 2>&1')
      end

      # Validate that the SSH key is a type supported by age
      # @param ssh_key_path [String] Path to the SSH private key (public key at .pub)
      # @return [true] if valid
      # @raise [EncryptionError] if key type is unsupported
      def validate_key_type!(ssh_key_path)
        raise EncryptionError, "Private key not found: #{ssh_key_path}" unless File.exist?(ssh_key_path)

        public_key = find_public_key(ssh_key_path)
        validate_public_key_type!(public_key)
      end

      def encrypt(content, ssh_key_path, output_file)
        raise EncryptionError, 'age encryption tool not available' unless available?

        public_key = find_public_key(ssh_key_path)
        run_age_encrypt(content, public_key, output_file)
      end

      # Decrypt an age-encrypted file using an SSH key
      # @param encrypted_file [String] Path to the encrypted file
      # @param ssh_key_path [String] Path to the SSH private key
      # @return [String, nil] Decrypted content, or nil if file doesn't exist
      # @raise [EncryptionError] If age tool not available, key not found, or decryption fails
      def decrypt(encrypted_file, ssh_key_path)
        return nil unless File.exist?(encrypted_file)

        raise EncryptionError, 'age encryption tool not available' unless available?
        raise EncryptionError, "SSH key not found: #{ssh_key_path}" unless File.exist?(ssh_key_path)

        run_age_decrypt(encrypted_file, ssh_key_path)
      end

      private

      def find_public_key(ssh_key_path)
        default_pub = "#{ssh_key_path}.pub"
        return default_pub if File.exist?(default_pub)

        if @on_prompt_pub_key
          prompted_path = @on_prompt_pub_key.call(ssh_key_path)
          return prompted_path if prompted_path && File.exist?(prompted_path)
        end

        raise EncryptionError, "Public key not found: #{default_pub}"
      end

      def validate_public_key_type!(public_key)
        first_line = File.read(public_key).lines.first&.strip || ''
        key_type = first_line.split.first

        return true if SUPPORTED_KEY_TYPES.include?(key_type)

        raise EncryptionError,
              "Unsupported SSH key type: #{key_type || 'unknown'}. " \
              "age only supports: #{SUPPORTED_KEY_TYPES.join(', ')}"
      end

      def run_age_encrypt(content, public_key, output_file)
        _output, error, status = Open3.capture3('age', '-R', public_key, '-o', output_file, stdin_data: content)
        raise EncryptionError, "Failed to encrypt: #{error.strip}" unless status.success?

        true
      end

      def run_age_decrypt(encrypted_file, ssh_key_path)
        output, error, status = Open3.capture3('age', '-d', '-i', ssh_key_path, encrypted_file)
        raise EncryptionError, "Failed to decrypt #{encrypted_file}: #{error.strip}" unless status.success?

        output
      rescue Errno::ENOENT => e
        raise EncryptionError, "Decryption failed: #{e.message}"
      end
    end
  end
end
