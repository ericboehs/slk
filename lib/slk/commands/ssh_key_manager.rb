# frozen_string_literal: true

module Slk
  module Commands
    # Handles SSH key configuration and token migration
    class SshKeyManager
      def initialize(config:, token_store:, output:)
        @config = config
        @token_store = token_store
        @output = output
      end

      def set(new_path)
        new_path = normalize_path(new_path)
        return error('Please provide the private key path, not the public key (.pub)') if pub_key?(new_path)

        migrate_tokens(@config.ssh_key, new_path)
        @config['ssh_key'] = new_path
        success_message(new_path)
      rescue EncryptionError => e
        error(e.message)
      end

      def unset
        old_path = resolve_old_path
        migrate_tokens(old_path, nil)
        @config['ssh_key'] = nil
        { success: true, message: 'Cleared ssh_key' }
      rescue EncryptionError => e
        error(e.message)
      end

      private

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
        path && !path.empty? ? File.expand_path(path) : nil
      end

      def encrypted_tokens_exist?
        paths = Support::XdgPaths.new
        File.exist?(paths.config_file('tokens.age'))
      end

      def migrate_tokens(old_path, new_path)
        @token_store.on_info = ->(msg) { @on_info&.call(msg) }
        @token_store.on_warning = ->(msg) { @on_warning&.call(msg) }
        @token_store.migrate_encryption(old_path, new_path)
      end

      def success_message(new_path)
        message = new_path ? "Set ssh_key = #{new_path}" : 'Cleared ssh_key'
        { success: true, message: message }
      end

      def error(message)
        { success: false, error: message }
      end

      public

      attr_accessor :on_info, :on_warning
    end
  end
end
