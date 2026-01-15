# frozen_string_literal: true

module Slk
  module Services
    # Handles saving tokens to encrypted or plaintext files
    class TokenSaver
      def initialize(encryption:, paths:)
        @encryption = encryption
        @paths = paths
      end

      def save(tokens, ssh_key)
        @paths.ensure_config_dir

        if ssh_key
          save_encrypted(tokens, ssh_key)
        else
          save_plaintext(tokens)
        end
      end

      def save_with_cleanup(tokens, ssh_key)
        @paths.ensure_config_dir

        if ssh_key
          save_encrypted(tokens, ssh_key)
          FileUtils.rm_f(plain_tokens_file)
        else
          save_plaintext(tokens)
          FileUtils.rm_f(encrypted_tokens_file)
        end
      end

      private

      def save_encrypted(tokens, ssh_key)
        @encryption.encrypt(JSON.generate(tokens), ssh_key, encrypted_tokens_file)
        FileUtils.rm_f(plain_tokens_file)
      end

      def save_plaintext(tokens)
        File.write(plain_tokens_file, JSON.pretty_generate(tokens))
        File.chmod(0o600, plain_tokens_file)
      end

      def encrypted_tokens_file
        @paths.config_file('tokens.age')
      end

      def plain_tokens_file
        @paths.config_file('tokens.json')
      end
    end
  end
end
