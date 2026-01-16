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
      # @raise [EncryptionError] if private key not found, public key not found,
      #   key type is unsupported, or public key doesn't match private key
      def validate_key_type!(ssh_key_path)
        raise EncryptionError, "Private key not found: #{ssh_key_path}" unless File.exist?(ssh_key_path)

        public_key = find_public_key(ssh_key_path)
        validate_public_key_type!(public_key)
        validate_key_pair_match!(ssh_key_path, public_key)
      end

      # Encrypt content using age with an SSH public key
      # @param content [String] The content to encrypt
      # @param ssh_key_path [String] Path to the SSH private key (public key at .pub)
      # @param output_file [String] Path where encrypted output will be written
      # @raise [EncryptionError] If age tool not available or public key not found
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

        prompted_path = prompt_and_validate_public_key(ssh_key_path)
        return prompted_path if prompted_path

        raise EncryptionError, "Public key not found: #{default_pub}"
      end

      def prompt_and_validate_public_key(ssh_key_path)
        return nil unless @on_prompt_pub_key

        prompted_path = @on_prompt_pub_key.call(ssh_key_path)
        return nil unless prompted_path && File.exist?(prompted_path)

        # Validate the prompted key before accepting it
        validate_public_key_type!(prompted_path)
        validate_key_pair_match!(ssh_key_path, prompted_path)
        prompted_path
      end

      def validate_public_key_type!(public_key)
        first_line = File.read(public_key).lines.first&.strip || ''
        key_type = first_line.split.first

        return true if SUPPORTED_KEY_TYPES.include?(key_type)

        raise EncryptionError,
              "Unsupported SSH key type: #{key_type || 'unknown'}. " \
              "age only supports: #{SUPPORTED_KEY_TYPES.join(', ')}"
      end

      def validate_key_pair_match!(private_key_path, public_key_path)
        derived_pub = derive_public_key(private_key_path)
        return true unless derived_pub # Skip validation if ssh-keygen not available

        provided_pub = File.read(public_key_path).lines.first&.strip || ''
        return true if keys_match?(derived_pub, provided_pub)

        raise EncryptionError,
              'Public key does not match private key. ' \
              'Please provide the correct public key for this private key.'
      end

      def derive_public_key(private_key_path)
        output, error, status = Open3.capture3('ssh-keygen', '-y', '-f', private_key_path)
        return output.strip if status.success?

        # Check if ssh-keygen is missing vs other failures
        return nil if ssh_keygen_not_found?(error)

        # For other failures (passphrase-protected, corrupted), warn the user
        raise EncryptionError,
              "Cannot verify key pair: #{error.strip}. " \
              'This may indicate a passphrase-protected or corrupted private key.'
      end

      # Heuristics for detecting missing ssh-keygen command.
      # These strings vary by OS/shell but cover common cases.
      def ssh_keygen_not_found?(error)
        error.include?('command not found') ||
          error.include?('not recognized') ||
          error.include?('No such file or directory')
      end

      # SSH public key format: "type base64-data comment"
      # Compare only type and key data, ignore the optional comment field
      def keys_match?(derived, provided)
        derived_parts = derived.split[0..1]
        provided_parts = provided.split[0..1]
        derived_parts == provided_parts
      end

      def run_age_encrypt(content, public_key, output_file)
        _output, error, status = Open3.capture3('age', '-R', public_key, '-o', output_file, stdin_data: content)
        raise EncryptionError, "Failed to encrypt: #{error.strip}" unless status.success?
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
