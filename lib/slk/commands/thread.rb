# frozen_string_literal: true

require_relative 'messages'

module Slk
  module Commands
    # Views a message thread from a Slack URL
    class Thread < Messages
      def execute
        result = validate_options
        return result if result

        target = positional_args.first
        return usage_error unless target

        parsed = Support::SlackUrlParser.new.parse(target)
        return url_required_error unless parsed&.message?

        resolved = target_resolver.resolve(target, default_workspace: target_workspaces.first)
        fetch_and_display_messages(resolved)
      rescue ApiError => e
        error("Failed to fetch messages: #{e.message}")
        1
      rescue ArgumentError => e
        error(e.message)
        1
      end

      def fetch_and_display_messages(resolved)
        ts = resolved.thread_ts || resolved.msg_ts
        return message_url_required_error unless ts

        api = runner.conversations_api(resolved.workspace.name)
        raw = fetch_all_thread_replies(api, resolved.channel_id, ts)
        messages = raw.map { |m| Models::Message.from_api(m, channel_id: resolved.channel_id) }

        output_messages(messages, resolved.workspace, resolved.channel_id)
        0
      end

      protected

      def usage_error
        error('Usage: slk thread <url>')
        1
      end

      def url_required_error
        error('thread command requires a Slack message URL')
        1
      end

      def message_url_required_error
        error('URL must point to a specific message (not just a channel)')
        1
      end

      def help_text
        help = Support::HelpFormatter.new('slk thread <url> [options]')
        help.description('View a message thread from a Slack URL.')
        add_usage_section(help)
        add_options_section(help)
        add_examples_section(help)
        help.render
      end

      private

      def add_usage_section(help)
        help.section('USAGE') { |s| s.item('<slack_url>', 'Slack message URL') }
      end

      def add_options_section(help)
        help.section('OPTIONS') do |s|
          s.option('--no-emoji', 'Show :emoji: codes instead of unicode')
          s.option('--no-reactions', 'Hide reactions')
          s.option('--no-names', 'Skip user name lookups (faster)')
          s.option('--fetch-attachments', 'Download files/images to local cache (~/.cache/slk/files/)')
          s.option('--json', 'Output as JSON')
          s.option('-v, --verbose', 'Show debug information')
        end
      end

      def add_examples_section(help)
        help.section('EXAMPLES') do |s|
          s.item('slk thread https://work.slack.com/archives/C123/p1234567890', 'View thread')
        end
      end
    end
  end
end
