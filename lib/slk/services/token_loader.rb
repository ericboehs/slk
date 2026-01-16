# frozen_string_literal: true

module Slk
  module Services
    # Handles loading tokens from encrypted or plaintext files
    class TokenLoader
      def initialize(encryption:, paths:)
        @encryption = encryption
        @paths = paths
      end

      def load(ssh_key)
        if encrypted_file_exists? && ssh_key
          decrypt_with_key(ssh_key)
        elsif encrypted_file_exists?
          raise EncryptionError, 'Cannot read encrypted tokens without SSH key'
        elsif plain_file_exists?
          parse_plain_file
        else
          {}
        end
      end

      def load_auto(config)
        if encrypted_file_exists?
          load_encrypted(config)
        elsif plain_file_exists?
          parse_plain_file
        else
          {}
        end
      end

      def load_encrypted(config)
        raise_missing_key_error unless config.ssh_key
        decrypt_with_key(config.ssh_key)
      end

      def raise_missing_key_error
        raise EncryptionError,
              'Cannot read encrypted tokens - no SSH key configured. Run: slk config set ssh_key <path>'
      end

      def encrypted_file_exists?
        File.exist?(encrypted_tokens_file)
      end

      def plain_file_exists?
        File.exist?(plain_tokens_file)
      end

      def encrypted_tokens_file
        @paths.config_file('tokens.age')
      end

      def plain_tokens_file
        @paths.config_file('tokens.json')
      end

      private

      def decrypt_with_key(ssh_key)
        content = @encryption.decrypt(encrypted_tokens_file, ssh_key)
        if content.nil?
          raise TokenStoreError, "Encrypted tokens file disappeared unexpectedly: #{encrypted_tokens_file}"
        end

        JSON.parse(content)
      rescue JSON::ParserError => e
        raise TokenStoreError, "Encrypted tokens file is corrupted: #{e.message}"
      end

      def parse_plain_file
        content = File.read(plain_tokens_file)
        JSON.parse(content)
      rescue Errno::ENOENT
        raise TokenStoreError, "Tokens file disappeared unexpectedly: #{plain_tokens_file}"
      rescue JSON::ParserError => e
        raise TokenStoreError, "Tokens file #{plain_tokens_file} is corrupted: #{e.message}"
      end
    end
  end
end
