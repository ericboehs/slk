# frozen_string_literal: true

require_relative '../support/help_formatter'

module Slk
  module Commands
    # Gets or sets user presence (away/active)
    class Presence < Base
      def execute
        result = validate_options
        return result if result

        dispatch_action
      rescue ApiError => e
        error("Failed: #{e.message}")
        1
      end

      private

      def dispatch_action
        case positional_args
        in ['away'] then set_presence('away')
        in ['auto' | 'active'] then set_presence('auto')
        in [] then get_presence
        else unknown_presence
        end
      end

      def unknown_presence
        error("Unknown presence: #{positional_args.first}")
        error('Valid options: away, auto, active')
        1
      end

      protected

      def help_text
        help = Support::HelpFormatter.new('slk presence [away|auto|active]')
        help.description('Get or set your presence status.')
        help.note('GET shows all workspaces by default. SET applies to primary only.')
        add_actions_section(help)
        add_options_section(help)
        help.render
      end

      def add_actions_section(help)
        help.section('ACTIONS') do |s|
          s.action('(none)', 'Show current presence (all workspaces)')
          s.action('away', 'Set presence to away')
          s.action('auto', 'Set presence to auto (active)')
          s.action('active', 'Alias for auto')
        end
      end

      def add_options_section(help)
        help.section('OPTIONS') do |s|
          s.option('-w, --workspace', 'Limit to specific workspace')
          s.option('--all', 'Set across all workspaces')
          s.option('-q, --quiet', 'Suppress output')
        end
      end

      private

      def get_presence # rubocop:disable Naming/AccessorMethodName
        workspaces = @options[:workspace] ? [runner.workspace(@options[:workspace])] : runner.all_workspaces
        workspaces.each { |workspace| display_workspace_presence(workspace, workspaces.size > 1) }
        0
      end

      def display_workspace_presence(workspace, show_header)
        data = runner.users_api(workspace.name).get_presence
        puts output.bold(workspace.name) if show_header
        puts "  Presence: #{format_presence_status(data[:presence], data[:manual_away])}"
      end

      def format_presence_status(presence, manual)
        case [presence, manual]
        in ['away', true] then output.yellow('away (manual)')
        in ['away', _] then output.yellow('away')
        in ['active', _] then output.green('active')
        else presence
        end
      end

      def set_presence(presence) # rubocop:disable Naming/AccessorMethodName
        target_workspaces.each do |workspace|
          runner.users_api(workspace.name).set_presence(presence)

          status_text = presence == 'away' ? output.yellow('away') : output.green('active')
          success("Presence set to #{status_text} on #{workspace.name}")
        end

        show_all_workspaces_hint

        0
      end

      def show_all_workspaces_hint
        # Show hint if user has multiple workspaces and didn't use --all or -w
        return if @options[:all] || @options[:workspace]
        return if runner.all_workspaces.size <= 1

        info('Tip: Use --all to set across all workspaces')
      end
    end
  end
end
