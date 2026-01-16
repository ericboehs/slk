# frozen_string_literal: true

module Slk
  module Commands
    # Handles SSH key configuration and token migration.
    # When the SSH key is changed, existing tokens are decrypted with the old key
    # and re-encrypted with the new key. Supports prompting for public key location
    # if not found at the default path (private_key.pub).
    class SshKeyManager
      # File system errors mapped to user-friendly messages.
      # These occur during SSH key file operations (reading keys, migrating tokens).
      FILE_ERRORS = {
        Errno::ENOENT => 'File not found',
        Errno::EACCES => 'Permission denied',
        Errno::EPERM => 'Permission denied',
        Errno::ENOSPC => 'Disk full',
        Errno::EDQUOT => 'Disk quota exceeded',
        Errno::EROFS => 'Read-only file system'
      }.freeze

      attr_accessor :on_info, :on_warning

      def initialize(config:, token_store:, output:)
        @config = config
        @token_store = token_store
        @output = output
      end

      def set(new_path)
        with_error_handling { perform_set(new_path) }
      end

      def unset
        with_error_handling { perform_unset }
      end

      private

      def perform_set(new_path)
        new_path = normalize_path(new_path)
        return error('Please provide the private key path, not the public key (.pub)') if pub_key?(new_path)

        migrate_tokens(@config.ssh_key, new_path)
        @config['ssh_key'] = new_path
        success_message(new_path)
      end

      def perform_unset
        old_path = resolve_old_path
        migrate_tokens(old_path, nil)
        @config['ssh_key'] = nil
        success('Cleared ssh_key')
      end

      def with_error_handling
        yield
      rescue EncryptionError => e
        error(e.message)
      rescue ArgumentError => e
        error("Invalid path: #{e.message}")
      rescue *FILE_ERRORS.keys => e
        error("#{FILE_ERRORS[e.class]}: #{e.message}")
      end

      def normalize_path(path)
        path == '' ? nil : File.expand_path(path)
      end

      def pub_key?(path)
        path&.end_with?('.pub')
      end

      def resolve_old_path
        old_path = @config.ssh_key
        old_path = nil if old_path.to_s.empty?

        return old_path if old_path || !encrypted_tokens_exist?

        prompt_for_key_path
      end

      def prompt_for_key_path
        @output.puts 'Encrypted tokens exist but no ssh_key is configured.'
        @output.print 'Enter path to SSH key for decryption: '
        path = $stdin.gets&.chomp

        if path.nil? || path.empty?
          raise EncryptionError, 'SSH key path required to decrypt existing tokens. Operation cancelled.'
        end

        File.expand_path(path)
      end

      def encrypted_tokens_exist?
        paths = Support::XdgPaths.new
        File.exist?(paths.config_file('tokens.age'))
      end

      def migrate_tokens(old_path, new_path)
        @token_store.on_info = ->(msg) { @on_info&.call(msg) }
        @token_store.on_warning = ->(msg) { @on_warning&.call(msg) }
        @token_store.on_prompt_pub_key = method(:prompt_for_pub_key)
        @token_store.migrate_encryption(old_path, new_path)
      end

      def prompt_for_pub_key(private_key_path)
        @output.puts "Public key not found at #{private_key_path}.pub"
        @output.print 'Enter path to public key (or press Enter to cancel): '
        path = $stdin.gets&.chomp
        return nil if path.nil? || path.empty?

        File.expand_path(path)
      end

      def success_message(new_path)
        message = new_path ? "Set ssh_key = #{new_path}" : 'Cleared ssh_key'
        success(message)
      end

      def success(message)
        { success: true, message: message }
      end

      def error(message)
        { success: false, error: message }
      end
    end
  end
end
