# frozen_string_literal: true

module Slk
  module Services
    # Interactive setup wizard for configuring workspaces
    class SetupWizard
      def initialize(runner:, config:, token_store:, output:)
        @runner = runner
        @config = config
        @token_store = token_store
        @output = output
      end

      # Run the setup wizard
      # @return [Integer] exit code (0 for success, 1 for error)
      def run
        print_header

        return 0 if skip_if_configured?

        setup_encryption unless @config.ssh_key
        result = setup_workspace
        return result if result != 0

        print_success
        0
      end

      private

      def print_header
        @output.puts 'Slack CLI Setup'
        @output.puts '==============='
        @output.puts
      end

      def skip_if_configured?
        return false unless @runner.workspaces?

        @output.puts 'You already have workspaces configured.'
        @output.print 'Add another workspace? (y/n): '
        answer = $stdin.gets&.chomp&.downcase
        answer != 'y'
      end

      def setup_encryption
        print_encryption_header
        ssh_key = $stdin.gets&.chomp
        configure_ssh_key(ssh_key) if ssh_key && !ssh_key.empty?
      end

      def print_encryption_header
        @output.puts
        @output.puts 'Encryption Setup (optional)'
        @output.puts '----------------------------'
        @output.puts 'You can encrypt your tokens with age using an SSH key.'
        @output.print 'SSH key path (or press Enter to skip): '
      end

      def configure_ssh_key(ssh_key)
        if File.exist?(ssh_key)
          @config.ssh_key = ssh_key
          @output.success('SSH key configured')
        else
          @output.warn("File not found: #{ssh_key}")
        end
      end

      def setup_workspace
        print_workspace_header
        name, token = prompt_credentials
        return 1 unless name && token

        save_workspace(name, token, prompt_cookie_if_needed(token))
        0
      end

      def print_workspace_header
        @output.puts
        @output.puts 'Workspace Setup'
        @output.puts '---------------'
      end

      def prompt_credentials
        [prompt_workspace_name, prompt_token]
      end

      def save_workspace(name, token, cookie)
        @token_store.add(name, token, cookie)
        @config.primary_workspace = name if @config.primary_workspace.nil?
      end

      def prompt_workspace_name
        @output.print 'Workspace name: '
        name = $stdin.gets&.chomp
        return name unless name.nil? || name.empty?

        @output.error('Name is required')
        nil
      end

      def prompt_token
        @output.print 'Token (xoxb-... or xoxc-...): '
        token = $stdin.gets&.chomp
        return token unless token.nil? || token.empty?

        @output.error('Token is required')
        nil
      end

      def prompt_cookie_if_needed(token)
        return nil unless token.start_with?('xoxc-')

        @output.puts
        @output.puts 'xoxc tokens require a cookie for authentication.'
        @output.print 'Cookie (d=...): '
        $stdin.gets&.chomp
      end

      def print_success
        @output.puts
        @output.success('Setup complete!')
        @output.puts
        @output.puts 'Try these commands:'
        @output.puts '  slk status           - View your status'
        @output.puts '  slk messages general - Read channel messages'
        @output.puts '  slk help             - See all commands'
      end
    end
  end
end
