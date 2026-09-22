# frozen_string_literal: true

module Slk
  module Formatters
    # Renders expanded sent-message conversations for people and scripts.
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

      private

      def payload(conversations, start_date, end_date)
        { date: start_date == end_date ? start_date.iso8601 : nil,
          range: start_date == end_date ? nil : { since: start_date.iso8601, through: end_date.iso8601 },
          conversations: conversations.map { |conversation| json_conversation(conversation) } }
      end

      def json_conversation(conversation)
        { workspace: conversation.workspace.name, channel_id: conversation.channel_id,
          channel_name: conversation.channel_name, type: conversation.type,
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
        conversation.messages.each { |message| display_message(message, conversation) }
      end

      # Header combines the resolved channel, optional thread root and signal.
      # rubocop:disable Metrics/AbcSize
      def display_header(conversation)
        label = @runner.search_formatter.channel_label_for(
          conversation.type, conversation.channel_name, conversation.workspace
        )
        heading = "[#{conversation.workspace.name}] #{label}"
        heading += " (thread: #{thread_snippet(conversation)})" if conversation.type == 'thread'
        @runner.output.puts heading
        signal = conversation.last_speaker_is_me ? '• you had the last word' : '↩ replied after you'
        @runner.output.puts signal
        return unless conversation.dropped_messages.positive?

        @runner.output.puts "(#{conversation.dropped_messages} older messages omitted by --max)"
      end
      # rubocop:enable Metrics/AbcSize

      def display_message(message, conversation)
        marker = mine?(message, conversation) ? '▶ ' : '  '
        formatted = @runner.message_formatter.format_simple(
          message, workspace: conversation.workspace, options: @options
        )
        @runner.output.puts "#{marker}#{formatted}"
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
  end
end
