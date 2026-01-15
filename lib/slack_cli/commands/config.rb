# frozen_string_literal: true

require_relative '../support/help_formatter'

module SlackCli
  module Commands
    # Manages CLI configuration settings
    class Config < Base
      def execute
        result = validate_options
        return result if result

        case positional_args
        in ['show'] | []
          show_config
        in ['setup'] | [_]
          run_setup
        in ['get', key]
          get_value(key)
        in ['set', key, value]
          set_value(key, value)
        end
      end

      protected

      def help_text
        help = Support::HelpFormatter.new('slk config [action]')
        help.description('Manage configuration.')

        help.section('ACTIONS') do |s|
          s.action('show', 'Show current configuration')
          s.action('setup', 'Run setup wizard')
          s.action('get <key>', 'Get a config value')
          s.action('set <key> <val>', 'Set a config value')
        end

        help.section('CONFIG KEYS') do |s|
          s.item('primary_workspace', 'Default workspace name')
          s.item('ssh_key', 'Path to SSH key for encryption')
          s.item('emoji_dir', 'Custom emoji directory')
        end

        help.section('OPTIONS') do |s|
          s.option('-q, --quiet', 'Suppress output')
        end

        help.render
      end

      private

      def show_config
        puts 'Configuration:'
        puts "  Primary workspace: #{config.primary_workspace || '(not set)'}"
        puts "  SSH key: #{config.ssh_key || '(not set)'}"
        puts "  Emoji dir: #{config.emoji_dir || '(default)'}"
        puts
        puts "Workspaces: #{runner.workspace_names.join(', ')}"
        puts
        paths = Support::XdgPaths.new
        puts "Config dir: #{paths.config_dir}"
        puts "Cache dir: #{paths.cache_dir}"

        0
      end

      def run_setup
        puts 'Slack CLI Setup'
        puts '==============='
        puts

        # Check for existing config
        if runner.workspaces?
          puts 'You already have workspaces configured.'
          print 'Add another workspace? (y/n): '
          answer = $stdin.gets&.chomp&.downcase
          return 0 unless answer == 'y'
        end

        # Setup encryption
        if config.ssh_key.nil?
          puts
          puts 'Encryption Setup (optional)'
          puts '----------------------------'
          puts 'You can encrypt your tokens with age using an SSH key.'
          print 'SSH key path (or press Enter to skip): '
          ssh_key = $stdin.gets&.chomp

          unless ssh_key.nil? || ssh_key.empty?
            if File.exist?(ssh_key)
              config.ssh_key = ssh_key
              success('SSH key configured')
            else
              warn("File not found: #{ssh_key}")
            end
          end
        end

        # Add workspace
        puts
        puts 'Workspace Setup'
        puts '---------------'

        print 'Workspace name: '
        name = $stdin.gets&.chomp
        return error('Name is required') if name.nil? || name.empty?

        print 'Token (xoxb-... or xoxc-...): '
        token = $stdin.gets&.chomp
        return error('Token is required') if token.nil? || token.empty?

        cookie = nil
        if token.start_with?('xoxc-')
          puts
          puts 'xoxc tokens require a cookie for authentication.'
          print 'Cookie (d=...): '
          cookie = $stdin.gets&.chomp
        end

        token_store.add(name, token, cookie)

        # Set as primary if first
        config.primary_workspace = name if config.primary_workspace.nil?

        puts
        success('Setup complete!')
        puts
        puts 'Try these commands:'
        puts '  slack status           - View your status'
        puts '  slack messages #general - Read channel messages'
        puts '  slack help             - See all commands'

        0
      end

      def get_value(key)
        value = config[key]
        puts value || '(not set)'

        0
      end

      def set_value(key, value)
        config[key] = value
        success("Set #{key} = #{value}")

        0
      end
    end
  end
end
