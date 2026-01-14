# frozen_string_literal: true

require_relative '../support/help_formatter'

module SlackCli
  module Commands
    class Dnd < Base
      def execute
        result = validate_options
        return result if result

        case positional_args
        in ['status' | 'info']
          get_status
        in ['on' | 'snooze', *rest]
          duration = Models::Duration.parse(rest.first || '1h')
          set_snooze(duration)
        in ['off' | 'end']
          end_snooze
        in [duration_str] if duration_str.match?(/^\d+[hms]?$/)
          duration = Models::Duration.parse(duration_str)
          set_snooze(duration)
        in []
          get_status
        else
          error("Unknown action: #{positional_args.first}")
          error('Valid actions: status, on, off, or a duration (e.g., 1h)')
          1
        end
      rescue ArgumentError => e
        error("Invalid duration: #{e.message}")
        1
      rescue ApiError => e
        error("Failed: #{e.message}")
        1
      end

      protected

      def help_text
        help = Support::HelpFormatter.new('slk dnd [action] [duration]')
        help.description('Manage Do Not Disturb (snooze) settings.')
        help.note('GET shows all workspaces by default. SET applies to primary only.')

        help.section('ACTIONS') do |s|
          s.action('(none)', 'Show current DND status (all workspaces)')
          s.action('status', 'Show current DND status')
          s.action('on [duration]', 'Enable snooze (default: 1h)')
          s.action('off', 'Disable snooze')
          s.action('<duration>', 'Enable snooze for specified duration')
        end

        help.section('DURATION FORMAT') do |s|
          s.item('1h', '1 hour')
          s.item('30m', '30 minutes')
          s.item('1h30m', '1 hour 30 minutes')
        end

        help.section('OPTIONS') do |s|
          s.option('-w, --workspace', 'Limit to specific workspace')
          s.option('--all', 'Set across all workspaces')
          s.option('-q, --quiet', 'Suppress output')
        end

        help.render
      end

      private

      def get_status
        # GET defaults to all workspaces unless -w specified
        workspaces = @options[:workspace] ? [runner.workspace(@options[:workspace])] : runner.all_workspaces

        workspaces.each do |workspace|
          api = runner.dnd_api(workspace.name)
          data = api.info

          puts output.bold(workspace.name) if workspaces.size > 1

          if data['snooze_enabled']
            remaining = api.snooze_remaining
            if remaining
              puts "  DND: #{output.yellow('snoozing')} (#{remaining} remaining)"
            else
              puts "  DND: #{output.yellow('snoozing')} (expired)"
            end
          else
            puts "  DND: #{output.green('off')}"
          end

          # Show scheduled DND if present
          next unless data['dnd_enabled']

          start_time = data['next_dnd_start_ts']
          end_time = data['next_dnd_end_ts']
          next unless start_time && end_time

          start_str = Time.at(start_time).strftime('%H:%M')
          end_str = Time.at(end_time).strftime('%H:%M')
          puts "  Schedule: #{start_str} - #{end_str}"
        end

        0
      end

      def set_snooze(duration)
        target_workspaces.each do |workspace|
          api = runner.dnd_api(workspace.name)
          api.set_snooze(duration)

          success("DND enabled for #{duration} on #{workspace.name}")
        end

        show_all_workspaces_hint

        0
      end

      def end_snooze
        target_workspaces.each do |workspace|
          api = runner.dnd_api(workspace.name)
          api.end_snooze

          success("DND disabled on #{workspace.name}")
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
