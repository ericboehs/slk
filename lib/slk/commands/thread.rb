# frozen_string_literal: true

require_relative 'messages'

module Slk
  module Commands
    # Views a message thread from a Slack URL, or subscribes to / unsubscribes
    # from it so new replies surface without posting in the thread
    # rubocop:disable Metrics/ClassLength
    class Thread < Messages
      SUBSCRIPTION_ACTIONS = %w[subscribe unsubscribe].freeze
      # Session-only endpoint: bot/user OAuth tokens get one of these back.
      TOKEN_ERRORS = %i[not_allowed_token_type unknown_method missing_scope].freeze

      def execute
        result = validate_options
        return result if result

        dispatch
      rescue ApiError => e
        error("Failed to fetch messages: #{e.message}")
        1
      rescue ArgumentError => e
        error(e.message)
        1
      end

      def dispatch
        action = positional_args.first
        return change_subscription(action, positional_args[1]) if SUBSCRIPTION_ACTIONS.include?(action)

        resolve_and_display_thread
      end

      def resolve_and_display_thread
        target = positional_args.first
        return usage_error unless target

        parsed = Support::SlackUrlParser.new.parse(target)
        return url_required_error unless parsed&.message?

        resolved = target_resolver.resolve(target, default_workspace: target_workspaces.first)
        fetch_and_display_messages(resolved)
      end

      def change_subscription(action, target)
        return subscription_usage_error(action) unless target
        return url_required_error unless Support::SlackUrlParser.new.parse(target)&.message?

        resolved = target_resolver.resolve(target, default_workspace: target_workspaces.first)
        report_subscription(action, resolved.workspace, apply_subscription(action, resolved))
      rescue ApiError => e
        subscription_error(action, e)
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
        error('       slk thread subscribe|unsubscribe <url>')
        1
      end

      def subscription_usage_error(action)
        error("Usage: slk thread #{action} <url>")
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
        help = Support::HelpFormatter.new('slk thread [subscribe|unsubscribe] <url> [options]')
        help.description('View a message thread from a Slack URL, or subscribe to it without replying.')
        help.note('Subscribing marks existing replies read; new replies show up in `slk unread`.')
        add_usage_section(help)
        add_actions_section(help)
        add_options_section(help)
        add_examples_section(help)
        help.render
      end

      private

      def apply_subscription(action, resolved)
        thread_subscription(resolved.workspace).public_send(
          action, channel_id: resolved.channel_id, timestamp: resolved.thread_ts || resolved.msg_ts
        )
      end

      def thread_subscription(workspace)
        Services::ThreadSubscription.new(
          conversations_api: runner.conversations_api(workspace.name),
          threads_api: runner.threads_api(workspace.name)
        )
      end

      def report_subscription(action, workspace, result)
        if @options[:json]
          output_json(subscription_json(action, workspace, result))
        else
          verb = action == 'subscribe' ? 'Subscribed to' : 'Unsubscribed from'
          success("#{verb} thread #{result.thread_ts} in #{channel_label(workspace, result.channel_id)}")
        end
        0
      end

      def subscription_json(action, workspace, result)
        { subscribed: action == 'subscribe', workspace: workspace.name, channel_id: result.channel_id,
          thread_ts: result.thread_ts, last_read: result.last_read }
      end

      def channel_label(workspace, channel_id)
        name = cache_store.get_channel_name(workspace.name, channel_id)
        name ? "##{name}" : channel_id
      end

      def subscription_error(action, err)
        error("Failed to #{action} #{action == 'subscribe' ? 'to' : 'from'} thread: #{err.message}")
        error('Thread subscriptions require a session (xoxc) token.') if TOKEN_ERRORS.include?(err.code)
        1
      end

      def add_usage_section(help)
        help.section('USAGE') { |s| s.item('<slack_url>', 'Slack message URL') }
      end

      def add_actions_section(help)
        help.section('ACTIONS') do |s|
          s.action('subscribe <url>', 'Follow the thread (get notified of new replies)')
          s.action('unsubscribe <url>', 'Stop following the thread')
        end
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
          s.item('slk thread subscribe https://work.slack.com/archives/C123/p1234567890', 'Follow thread')
          s.item('slk thread unsubscribe https://work.slack.com/archives/C123/p1234567890', 'Unfollow thread')
        end
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
