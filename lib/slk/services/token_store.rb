# frozen_string_literal: true

module Slk
  module Services
    # Manages workspace tokens with optional encryption
    class TokenStore
      attr_accessor :on_warning, :on_info

      def initialize(config: nil, encryption: nil, paths: nil)
        @config = config || Configuration.new
        @encryption = encryption || Encryption.new
        @paths = paths || Support::XdgPaths.new
        @on_warning = nil
        @on_info = nil
      end

      def workspace(name)
        tokens = load_tokens
        data = tokens[name]
        raise WorkspaceNotFoundError, "Workspace '#{name}' not found" unless data

        Models::Workspace.new(
          name: name,
          token: data['token'],
          cookie: data['cookie']
        )
      end

      def all_workspaces
        load_tokens.map do |name, data|
          Models::Workspace.new(
            name: name,
            token: data['token'],
            cookie: data['cookie']
          )
        end
      end

      def workspace_names
        load_tokens.keys
      end

      def exists?(name)
        load_tokens.key?(name)
      end

      def add(name, token, cookie = nil)
        # Validate by constructing a Workspace (will raise ArgumentError if invalid)
        Models::Workspace.new(name: name, token: token, cookie: cookie)

        tokens = load_tokens
        tokens[name] = { 'token' => token, 'cookie' => cookie }.compact
        save_tokens(tokens)
      end

      def remove(name) # rubocop:disable Naming/PredicateMethod
        tokens = load_tokens
        removed = tokens.delete(name)
        save_tokens(tokens) if removed
        !removed.nil?
      end

      def empty?
        load_tokens.empty?
      end

      # Migrate tokens when encryption settings change
      # @param old_ssh_key [String, nil] Previous SSH key path (nil if was plaintext)
      # @param new_ssh_key [String, nil] New SSH key path (nil to decrypt to plaintext)
      # @raise [EncryptionError] If migration fails
      def migrate_encryption(old_ssh_key, new_ssh_key)
        return if old_ssh_key == new_ssh_key

        # Load tokens using the old key first - if empty, nothing to migrate
        tokens = load_tokens_with_key(old_ssh_key)
        return if tokens.empty?

        # Validate new key type before attempting migration
        @encryption.validate_key_type!(new_ssh_key) if new_ssh_key

        # Save with new encryption setting
        save_tokens_with_key(tokens, new_ssh_key)

        # Notify user of the change
        notify_encryption_change(new_ssh_key)
      end

      private

      def load_tokens
        if encrypted_file_exists?
          decrypt_tokens
        elsif plain_file_exists?
          JSON.parse(File.read(plain_tokens_file))
        else
          {}
        end
      rescue JSON::ParserError => e
        raise TokenStoreError, "Tokens file #{plain_tokens_file} is corrupted: #{e.message}"
      end

      def load_tokens_with_key(ssh_key)
        if encrypted_file_exists? && ssh_key
          content = @encryption.decrypt(encrypted_tokens_file, ssh_key)
          content ? JSON.parse(content) : {}
        elsif encrypted_file_exists? && !ssh_key
          # Encrypted file exists but no key provided - can't decrypt
          raise EncryptionError, 'Cannot read encrypted tokens without SSH key'
        elsif plain_file_exists?
          JSON.parse(File.read(plain_tokens_file))
        else
          {}
        end
      rescue JSON::ParserError => e
        raise TokenStoreError, "Tokens file is corrupted: #{e.message}"
      end

      def save_tokens(tokens)
        @paths.ensure_config_dir

        if @config.ssh_key
          # When encryption is configured, always use it - don't silently fall back
          @encryption.encrypt(JSON.generate(tokens), @config.ssh_key, encrypted_tokens_file)
          FileUtils.rm_f(plain_tokens_file)
        else
          # Plain text storage (no encryption configured)
          File.write(plain_tokens_file, JSON.pretty_generate(tokens))
          File.chmod(0o600, plain_tokens_file)
        end
      end

      def save_tokens_with_key(tokens, ssh_key)
        @paths.ensure_config_dir

        if ssh_key
          @encryption.encrypt(JSON.generate(tokens), ssh_key, encrypted_tokens_file)
          FileUtils.rm_f(plain_tokens_file)
        else
          File.write(plain_tokens_file, JSON.pretty_generate(tokens))
          File.chmod(0o600, plain_tokens_file)
          FileUtils.rm_f(encrypted_tokens_file)
        end
      end

      def notify_encryption_change(new_ssh_key)
        if new_ssh_key
          @on_info&.call('Tokens have been encrypted with the new SSH key.')
        else
          @on_warning&.call('Tokens are now stored in plaintext.')
        end
      end

      def decrypt_tokens
        content = @encryption.decrypt(encrypted_tokens_file, @config.ssh_key)
        content ? JSON.parse(content) : {}
      rescue JSON::ParserError => e
        raise TokenStoreError, "Encrypted tokens file is corrupted: #{e.message}"
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
    end
  end
end
