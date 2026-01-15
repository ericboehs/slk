# frozen_string_literal: true

module SlackCli
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
        @output.puts
        @output.puts 'Encryption Setup (optional)'
        @output.puts '----------------------------'
        @output.puts 'You can encrypt your tokens with age using an SSH key.'
        @output.print 'SSH key path (or press Enter to skip): '
        ssh_key = $stdin.gets&.chomp

        return if ssh_key.nil? || ssh_key.empty?

        if File.exist?(ssh_key)
          @config.ssh_key = ssh_key
          @output.success('SSH key configured')
        else
          @output.warn("File not found: #{ssh_key}")
        end
      end

      def setup_workspace
        @output.puts
        @output.puts 'Workspace Setup'
        @output.puts '---------------'

        name = prompt_workspace_name
        return 1 unless name

        token = prompt_token
        return 1 unless token

        cookie = prompt_cookie_if_needed(token)

        @token_store.add(name, token, cookie)
        @config.primary_workspace = name if @config.primary_workspace.nil?

        0
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
        @output.puts '  slack status           - View your status'
        @output.puts '  slack messages #general - Read channel messages'
        @output.puts '  slack help             - See all commands'
      end
    end
  end
end
