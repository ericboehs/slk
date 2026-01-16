# frozen_string_literal: true

module Slk
  module Services
    # Handles saving tokens to encrypted or plaintext files.
    # Uses atomic writes (temp file + mv) for the token file itself.
    class TokenSaver
      # File system errors we catch and wrap in TokenStoreError
      FILE_ERRORS = [
        Errno::ENOENT,
        Errno::EACCES,
        Errno::EPERM,
        Errno::ENOSPC,
        Errno::EDQUOT,
        Errno::EROFS,
        Errno::EIO
      ].freeze

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
        temp_file = "#{encrypted_tokens_file}.tmp"
        @encryption.encrypt(JSON.generate(tokens), ssh_key, temp_file)
        FileUtils.mv(temp_file, encrypted_tokens_file)
        FileUtils.rm_f(plain_tokens_file)
      rescue EncryptionError => e
        FileUtils.rm_f(temp_file)
        raise TokenStoreError, "Failed to encrypt tokens: #{e.message}"
      rescue *FILE_ERRORS => e
        FileUtils.rm_f(temp_file)
        raise TokenStoreError, "Failed to save encrypted tokens: #{e.message}"
      end

      def save_plaintext(tokens)
        temp_file = "#{plain_tokens_file}.tmp"
        File.write(temp_file, JSON.pretty_generate(tokens))
        restrict_file_permissions(temp_file)
        FileUtils.mv(temp_file, plain_tokens_file)
      rescue *FILE_ERRORS => e
        FileUtils.rm_f(temp_file)
        raise TokenStoreError, "Failed to save tokens: #{e.message}"
      end

      # Restrict file to owner-only access.
      # On Unix: chmod 600. On Windows: chmod is a no-op for security;
      # files in %APPDATA% are already user-private by default.
      def restrict_file_permissions(file)
        File.chmod(0o600, file) unless Gem.win_platform?
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
