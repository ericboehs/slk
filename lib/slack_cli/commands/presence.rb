# frozen_string_literal: true

require_relative '../support/help_formatter'

module SlackCli
  module Commands
    class Presence < Base
      def execute
        result = validate_options
        return result if result

        case positional_args
        in ['away']
          set_presence('away')
        in ['auto' | 'active']
          set_presence('auto')
        in []
          get_presence
        else
          error("Unknown presence: #{positional_args.first}")
          error('Valid options: away, auto, active')
          1
        end
      rescue ApiError => e
        error("Failed: #{e.message}")
        1
      end

      protected

      def help_text
        help = Support::HelpFormatter.new('slk presence [away|auto|active]')
        help.description('Get or set your presence status.')
        help.note('GET shows all workspaces by default. SET applies to primary only.')

        help.section('ACTIONS') do |s|
          s.action('(none)', 'Show current presence (all workspaces)')
          s.action('away', 'Set presence to away')
          s.action('auto', 'Set presence to auto (active)')
          s.action('active', 'Alias for auto')
        end

        help.section('OPTIONS') do |s|
          s.option('-w, --workspace', 'Limit to specific workspace')
          s.option('--all', 'Set across all workspaces')
          s.option('-q, --quiet', 'Suppress output')
        end

        help.render
      end

      private

      def get_presence
        # GET defaults to all workspaces unless -w specified
        workspaces = @options[:workspace] ? [runner.workspace(@options[:workspace])] : runner.all_workspaces

        workspaces.each do |workspace|
          data = runner.users_api(workspace.name).get_presence

          puts output.bold(workspace.name) if workspaces.size > 1

          presence = data[:presence]
          manual = data[:manual_away]

          status = case [presence, manual]
                   in ['away', true]
                     output.yellow('away (manual)')
                   in ['away', _]
                     output.yellow('away')
                   in ['active', _]
                     output.green('active')
                   else
                     presence
                   end

          puts "  Presence: #{status}"
        end

        0
      end

      def set_presence(presence)
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
