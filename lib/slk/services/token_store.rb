# frozen_string_literal: true

require_relative 'token_loader'
require_relative 'token_saver'

module Slk
  module Services
    # Manages workspace tokens with optional encryption
    class TokenStore
      attr_accessor :on_warning, :on_info, :on_prompt_pub_key

      def initialize(config: nil, encryption: nil, paths: nil)
        @config = config || Configuration.new
        @encryption = encryption || Encryption.new
        @paths = paths || Support::XdgPaths.new
        @loader = TokenLoader.new(encryption: @encryption, paths: @paths)
        @saver = TokenSaver.new(encryption: @encryption, paths: @paths)
        @on_warning = nil
        @on_info = nil
        @on_prompt_pub_key = nil
      end

      def workspace(name)
        tokens = @loader.load_auto(@config)
        data = tokens[name]
        raise WorkspaceNotFoundError, "Workspace '#{name}' not found" unless data

        Models::Workspace.new(name: name, token: data['token'], cookie: data['cookie'])
      end

      def all_workspaces
        @loader.load_auto(@config).map do |name, data|
          Models::Workspace.new(name: name, token: data['token'], cookie: data['cookie'])
        end
      end

      def workspace_names
        @loader.load_auto(@config).keys
      end

      def exists?(name)
        @loader.load_auto(@config).key?(name)
      end

      def add(name, token, cookie = nil)
        Models::Workspace.new(name: name, token: token, cookie: cookie)
        tokens = @loader.load_auto(@config)
        tokens[name] = { 'token' => token, 'cookie' => cookie }.compact
        @saver.save(tokens, @config.ssh_key)
      end

      def remove(name) # rubocop:disable Naming/PredicateMethod
        tokens = @loader.load_auto(@config)
        removed = tokens.delete(name)
        @saver.save(tokens, @config.ssh_key) if removed
        !removed.nil?
      end

      def empty?
        @loader.load_auto(@config).empty?
      end

      def migrate_encryption(old_ssh_key, new_ssh_key)
        return if old_ssh_key == new_ssh_key

        tokens = @loader.load(old_ssh_key)
        return if tokens.empty?

        @encryption.on_prompt_pub_key = @on_prompt_pub_key
        @encryption.validate_key_type!(new_ssh_key) if new_ssh_key
        @saver.save_with_cleanup(tokens, new_ssh_key)
        notify_encryption_change(old_ssh_key, new_ssh_key)
      end

      private

      def notify_encryption_change(old_ssh_key, new_ssh_key)
        if new_ssh_key && old_ssh_key
          @on_info&.call('Tokens have been re-encrypted with the new SSH key.')
        elsif new_ssh_key
          @on_info&.call('Tokens have been encrypted with the new SSH key.')
        else
          @on_warning&.call('Tokens are now stored in plaintext.')
        end
      end
    end
  end
end
