# frozen_string_literal: true

module Slk
  module Formatters
    # Renders expanded sent-message conversations for people and scripts.
    # rubocop:disable Metrics/ClassLength
    class SentFormatter
      def initialize(runner:, options: {})
        @runner = runner
        @options = options
        @names = {}
      end

      def display(conversations, start_date:, end_date:, json: false)
        if json
          @runner.output.puts(JSON.pretty_generate(payload(conversations, start_date, end_date)))
        else
          display_text(conversations)
        end
      end

      def display_changes(changes, changed_since:, lookback_days:, json: false)
        if json
          @runner.output.puts(JSON.pretty_generate(changes_payload(changes, changed_since, lookback_days)))
        else
          display_changed_text(changes, changed_since)
        end
      end

      private

      def payload(conversations, start_date, end_date)
        { date: start_date == end_date ? start_date.iso8601 : nil,
          range: start_date == end_date ? nil : { since: start_date.iso8601, through: end_date.iso8601 },
          conversations: conversations.map { |conversation| json_conversation(conversation) } }
      end

      def changes_payload(changes, since, days)
        { date: nil, range: { since: (Date.today - days + 1).iso8601, through: Date.today.iso8601 },
          changed_since: { iso: since.iso8601(since.usec.zero? ? 0 : 6),
                           ts: Support::CheckInTime.timestamp(since) },
          lookback_days: days, conversations: changes.map { |change| json_change(change) } }
      end

      def json_change(change)
        conversation = change.conversation
        json_conversation(conversation).merge(
          new_count: change.new_count, new_from_others: change.new_from_others,
          messages: conversation.messages.map do |message|
            json_message(message, conversation).merge(new: change.new_timestamps.include?(message.ts))
          end
        )
      end

      def json_conversation(conversation)
        { workspace: conversation.workspace.name, channel_id: conversation.channel_id,
          channel_name: conversation.channel_name, channel_label: channel_label(conversation), type: conversation.type,
          thread_ts: conversation.thread_ts, last_speaker_is_me: conversation.last_speaker_is_me,
          dropped_messages: conversation.dropped_messages,
          messages: conversation.messages.map { |message| json_message(message, conversation) } }
      end

      def json_message(message, conversation)
        { ts: message.ts, user: message.user_id, user_name: user_name(message, conversation.workspace),
          text: message.text, mine: mine?(message, conversation), thread_ts: message.thread_ts }
      end

      def user_name(message, workspace)
        key = [workspace.name, message.user_id]
        @names[key] ||= message.embedded_username || @runner.cache_store.get_user(workspace.name, message.user_id) ||
                        Services::UserLookup.new(cache_store: @runner.cache_store, workspace: workspace,
                                                 api_client: @runner.api_client).resolve_name_or_bot(message.user_id) ||
                        message.user_id
      end

      def display_text(conversations)
        return @runner.output.puts 'No sent conversations found.' if conversations.empty?

        conversations.each do |conversation|
          display_conversation(conversation)
          @runner.output.puts
        end
      end

      def display_conversation(conversation)
        display_header(conversation)
        display_messages(conversation.messages, conversation)
      end

      def display_changed_text(changes, since)
        return @runner.output.puts 'No changed sent conversations found.' if changes.empty?

        changes.each do |change|
          display_changed_conversation(change, since)
          @runner.output.puts
        end
      end

      def display_changed_conversation(change, since)
        conversation = change.conversation
        display_header(conversation, summary: "#{change.new_count} new (#{change.new_from_others} from others)")
        context, fresh = conversation.messages.partition { |message| !change.new_timestamps.include?(message.ts) }
        display_messages(context, conversation, context: true)
        @runner.output.puts "── new since #{since.strftime('%H:%M')} ──"
        display_messages(fresh, conversation, parent_timestamps: context.map(&:ts))
      end

      def display_messages(messages, conversation, context: false, parent_timestamps: [])
        replies = replies_by_parent(messages)
        messages.each do |message|
          next if replies.key?(message.thread_ts) && message.reply?

          display_message(message, conversation,
                          orphan: message.reply? && !parent_timestamps.include?(message.thread_ts), context: context)
          replies.fetch(message.ts, []).each { |reply| display_message(reply, conversation, context: context) }
        end
      end

      def replies_by_parent(messages)
        timestamps = messages.to_h { |message| [message.ts, true] }
        messages.select { |message| message.reply? && timestamps.key?(message.thread_ts) }
                .group_by(&:thread_ts)
      end

      # Header combines the resolved channel, optional thread root and signal.
      def display_header(conversation, summary: nil)
        @runner.output.puts wrap_heading(heading_for(conversation, summary))
        signal = conversation.last_speaker_is_me ? '• you had the last word' : '↩ replied after you'
        @runner.output.puts signal
        return unless conversation.dropped_messages.positive?

        @runner.output.puts "(#{conversation.dropped_messages} older messages omitted by --max)"
      end

      def heading_for(conversation, summary)
        heading = "[#{conversation.workspace.name}] #{channel_label(conversation)}"
        heading += " (thread: #{thread_snippet(conversation)})" if conversation.type == 'thread'
        heading += " — #{summary}" if summary
        heading
      end

      def display_message(message, conversation, orphan: false, context: false)
        display_orphan_reference(message, context) if orphan
        prefix = message.reply? ? '    ↳ ' : ''
        prefix = "· #{prefix}" if context
        line = "#{prefix}#{formatted_message(message, conversation, prefix)}"
        @runner.output.puts(context ? @runner.output.gray(line) : line)
      end

      def display_orphan_reference(message, context)
        line = "    (thread #{message.thread_ts})"
        line = "· #{line}" if context
        @runner.output.puts(context ? @runner.output.gray(line) : line)
      end

      def formatted_message(message, conversation, prefix)
        indent = ' ' * Support::TextWrapper.visible_length(prefix)
        options = @options.dup
        options[:width] -= indent.length if options[:width]
        formatted = @runner.message_formatter.format(message, workspace: conversation.workspace, options: options)
        indent.empty? ? formatted : formatted.gsub("\n", "\n#{indent}")
      end

      def wrap_heading(heading)
        width = @options[:width]
        return heading unless width && width > 2

        Support::TextWrapper.wrap(heading, width, width - 2).gsub("\n", "\n  ")
      end

      def channel_label(conversation)
        @runner.sent_channel_label.label(
          workspace: conversation.workspace, type: conversation.channel_type,
          name: conversation.channel_name, channel_id: conversation.channel_id,
          self_user_id: conversation.self_user_id, self_username: conversation.self_username
        )
      end

      def thread_snippet(conversation)
        text = conversation.parent_text.to_s.split("\n").first.to_s
        %("#{text[0, 80]}")
      end

      def mine?(message, conversation)
        # The search result provides the authenticated sender's user ID. It
        # remains attached to each conversation even if the first message is
        # an older parent from someone else.
        message.user_id == conversation.self_user_id
      end
    end
    # rubocop:enable Metrics/ClassLength
  end
end
