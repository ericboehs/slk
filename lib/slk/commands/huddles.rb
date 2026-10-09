# frozen_string_literal: true

require_relative '../support/help_formatter'

module Slk
  module Commands
    # List active huddles by grouping users.list profiles that share a call id.
    class Huddles < Base
      def execute
        result = validate_options
        return result if result
        return unexpected_argument if positional_args.any?

        emit(Services::HuddleFetch.new(runner: runner, output: output).call(target_workspaces))
        0
      rescue ApiError => e
        error("API error: #{e.message}")
      end

      protected

      def help_text
        help = Support::HelpFormatter.new('slk huddles [options]')
        help.description('List active huddles.')
        help.note('Slack has no huddle list. This reads huddle_state from users.list')
        help.note('and groups people who share a call id. The roster is fetched live.')
        help.note('Primary workspace only. --all scans every workspace at the same time.')
        help.note('A Slack Connect guest not in the roster is omitted.')
        add_options_section(help)
        add_examples_section(help)
        help.render
      end

      private

      def add_options_section(help)
        help.section('OPTIONS') do |section|
          section.option('-w, --workspace NAME', 'Limit to one workspace')
          section.option('--all', 'Scan every workspace')
          section.option('--json', 'Call id, channel, and participants')
        end
      end

      def add_examples_section(help)
        help.section('EXAMPLES') do |section|
          section.example('slk huddles', 'Active huddles on the primary workspace')
          section.example('slk huddles --all', 'Every configured workspace')
          section.example('slk huddles --json', 'Machine-readable')
        end
      end

      def unexpected_argument
        error("Unexpected argument: #{positional_args.first}.")
        1
      end

      def emit(reports)
        return output_json(json_documents(reports)) if @options[:json]
        return if @options[:quiet]

        Formatters::HuddleFormatter.new(output).render(reports, scope: single_workspace_scope(reports))
      end

      # A primary-only scan is easy to read as "nobody, anywhere" when other
      # workspaces are configured. Name the one that was actually checked.
      def single_workspace_scope(reports)
        return nil unless reports.one?
        return nil if runner.all_workspaces.size <= 1

        reports.first.workspace
      end

      # One workspace prints its document alone; several are keyed by name,
      # matching `slk unread --json`, so the output pipes straight into jq.
      def json_documents(reports)
        documents = reports.to_h { |report| [report.workspace, document(report)] }
        reports.one? ? documents.values.first : documents
      end

      def document(report)
        { huddles: report.huddles.map { |huddle| huddle_json(huddle) } }
      end

      def huddle_json(huddle)
        {
          call_id: huddle.call_id,
          channel_id: huddle.channel_id,
          channel: huddle.channel,
          participants: huddle.participants.map { |person| { id: person.id, name: person.name } }
        }
      end
    end
  end
end
