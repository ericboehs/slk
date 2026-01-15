# frozen_string_literal: true

require_relative '../support/help_formatter'

module SlackCli
  module Commands
    # Manages configured Slack workspaces
    # rubocop:disable Metrics/ClassLength
    class Workspaces < Base
      def execute
        result = validate_options
        return result if result

        dispatch_action
      end

      def dispatch_action
        case positional_args
        in ['list'] | [] then list_workspaces
        in ['add'] then add_workspace
        in ['remove', name] then remove_workspace(name)
        in ['primary'] then show_primary
        in ['primary', name] then set_primary(name)
        else unknown_action
        end
      end

      def unknown_action
        error("Unknown action: #{positional_args.first}")
        1
      end

      protected

      def help_text
        help = Support::HelpFormatter.new('slk workspaces <action> [name]')
        help.description('Manage Slack workspaces.')
        add_actions_section(help)
        add_options_section(help)
        help.render
      end

      def add_actions_section(help)
        help.section('ACTIONS') do |s|
          s.action('list', 'List configured workspaces')
          s.action('add', 'Add a new workspace (interactive)')
          s.action('remove <name>', 'Remove a workspace')
          s.action('primary', 'Show primary workspace')
          s.action('primary <name>', 'Set primary workspace')
        end
      end

      def add_options_section(help)
        help.section('OPTIONS') do |s|
          s.option('-q, --quiet', 'Suppress output')
        end
      end

      private

      def list_workspaces
        names = runner.workspace_names
        return show_no_workspaces if names.empty?

        print_workspace_list(names, config.primary_workspace)
        0
      end

      def show_no_workspaces
        puts 'No workspaces configured.'
        puts "Run 'slack workspaces add' to add one."
        0
      end

      def print_workspace_list(names, primary)
        puts 'Workspaces:'
        names.each do |name|
          marker = name == primary ? output.green('*') : ' '
          puts "  #{marker} #{name}"
        end
      end

      def add_workspace
        name = prompt_for_name
        return name if name.is_a?(Integer) # Error code

        token, cookie = prompt_for_credentials
        return token if token.is_a?(Integer) # Error code

        save_workspace(name, token, cookie)
      end

      def prompt_for_name
        print 'Workspace name: '
        name = $stdin.gets&.chomp
        return error('Name is required') if name.nil? || name.empty?
        return error("Workspace '#{name}' already exists") if token_store.exists?(name)

        name
      end

      def prompt_for_credentials
        print 'Token (xoxb-... or xoxc-...): '
        token = $stdin.gets&.chomp
        return error('Token is required') if token.nil? || token.empty?

        cookie = prompt_for_cookie(token)
        [token, cookie]
      end

      def prompt_for_cookie(token)
        return nil unless token.start_with?('xoxc-')

        print 'Cookie (d=...): '
        $stdin.gets&.chomp
      end

      def save_workspace(name, token, cookie)
        token_store.add(name, token, cookie)

        if runner.workspace_names.size == 1
          config.primary_workspace = name
          success("Added workspace '#{name}' (set as primary)")
        else
          success("Added workspace '#{name}'")
        end
        0
      end

      def remove_workspace(name)
        return error("Workspace '#{name}' not found") unless token_store.exists?(name)

        token_store.remove(name)
        handle_primary_after_removal(name)
        0
      end

      def handle_primary_after_removal(name)
        return success("Removed workspace '#{name}'") unless config.primary_workspace == name

        remaining = runner.workspace_names
        if remaining.any?
          config.primary_workspace = remaining.first
          success("Removed workspace '#{name}'. Primary changed to '#{remaining.first}'")
        else
          config.primary_workspace = nil
          success("Removed workspace '#{name}'")
        end
      end

      def show_primary
        primary = config.primary_workspace
        puts primary ? "Primary workspace: #{primary}" : 'No primary workspace set.'
        0
      end

      def set_primary(name) # rubocop:disable Naming/AccessorMethodName
        return error("Workspace '#{name}' not found") unless token_store.exists?(name)

        config.primary_workspace = name
        success("Primary workspace set to '#{name}'")

        0
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
