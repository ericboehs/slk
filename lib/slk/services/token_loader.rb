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
          decrypt_with_key(config.ssh_key)
        elsif plain_file_exists?
          parse_plain_file
        else
          {}
        end
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
        content ? JSON.parse(content) : {}
      rescue JSON::ParserError => e
        raise TokenStoreError, "Encrypted tokens file is corrupted: #{e.message}"
      end

      def parse_plain_file
        JSON.parse(File.read(plain_tokens_file))
      rescue JSON::ParserError => e
        raise TokenStoreError, "Tokens file #{plain_tokens_file} is corrupted: #{e.message}"
      end
    end
  end
end
