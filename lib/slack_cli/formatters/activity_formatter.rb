# frozen_string_literal: true

module SlackCli
  module Formatters
    # Formats activity feed items for terminal display
    class ActivityFormatter
      def initialize(output:, enricher:, emoji_replacer:, mention_replacer:, on_debug: nil)
        @output = output
        @enricher = enricher
        @emoji = emoji_replacer
        @mentions = mention_replacer
        @on_debug = on_debug
      end

      # Display a list of activity items
      def display_all(items, workspace, options: {})
        return puts 'No activity found.' if items.empty?

        items.each do |item|
          display_item(item, workspace, options)
        end
      end

      # Display a single activity item
      def display_item(item, workspace, options)
        type = item.dig('item', 'type')
        timestamp = format_time(item['feed_ts'])

        case type
        when 'message_reaction'
          display_reaction(item, workspace, timestamp, options)
        when 'at_user', 'at_user_group', 'at_channel', 'at_everyone'
          display_mention(item, workspace, timestamp, options)
        when 'thread_v2'
          display_thread(item, workspace, timestamp, options)
        when 'bot_dm_bundle'
          display_bot_dm(item, workspace, timestamp, options)
        else
          @on_debug&.call("Unknown activity type '#{type}' - skipping") if type
        end
      end

      private

      def display_reaction(item, workspace, timestamp, options)
        reaction_data = item.dig('item', 'reaction')
        message_data = item.dig('item', 'message')
        return debug_missing('reaction') unless reaction_data && message_data

        username = @enricher.resolve_user(workspace, reaction_data['user'])
        emoji = @emoji.lookup_emoji(reaction_data['name']) || ":#{reaction_data['name']}:"
        channel = @enricher.resolve_channel(workspace, message_data['channel'])

        puts "#{@output.blue(timestamp)} #{@output.bold(username)} reacted #{emoji} in #{channel}"
        show_message_preview(workspace, message_data, options)
      end

      def display_mention(item, workspace, timestamp, options)
        message_data = item.dig('item', 'message')
        return debug_missing('mention') unless message_data

        user_id = message_data['author_user_id'] || message_data['user']
        username = @enricher.resolve_user(workspace, user_id)
        channel = @enricher.resolve_channel(workspace, message_data['channel'])

        puts "#{@output.blue(timestamp)} #{@output.bold(username)} mentioned you in #{channel}"
        show_message_preview(workspace, message_data, options)
      end

      def display_thread(item, workspace, timestamp, options)
        thread_entry = item.dig('item', 'bundle_info', 'payload', 'thread_entry')
        return debug_missing('thread') unless thread_entry

        channel = @enricher.resolve_channel(workspace, thread_entry['channel_id'])
        puts "#{@output.blue(timestamp)} Thread activity in #{channel}"

        return unless options[:show_messages] && thread_entry['thread_ts']

        message_data = { 'channel' => thread_entry['channel_id'], 'ts' => thread_entry['thread_ts'] }
        show_message_preview(workspace, message_data, options)
      end

      def display_bot_dm(item, workspace, timestamp, options)
        message_data = item.dig('item', 'bundle_info', 'payload', 'message')
        return debug_missing('bot DM') unless message_data

        channel = @enricher.resolve_channel(workspace, message_data['channel'])
        puts "#{@output.blue(timestamp)} Bot message in #{channel}"
        show_message_preview(workspace, message_data, options)
      end

      def show_message_preview(workspace, message_data, options)
        return unless options[:show_messages]
        return unless options[:fetch_message]

        message = options[:fetch_message].call(workspace, message_data['channel'], message_data['ts'])
        display_message_content(message, workspace) if message
      end

      def display_message_content(message, workspace)
        username = resolve_message_author(message, workspace)
        text = prepare_message_text(message, workspace)

        lines = text.lines
        first_line = truncate(lines.first&.strip || text, 100)
        puts "  └─ #{username}: #{first_line}"

        display_additional_lines(lines) if lines.length > 1
      end

      def resolve_message_author(message, workspace)
        if message['user']
          @enricher.resolve_user(workspace, message['user'])
        elsif message['bot_id']
          'Bot'
        else
          'Unknown'
        end
      end

      def prepare_message_text(message, workspace)
        text = message['text'] || ''
        return '[No text]' if text.empty?

        @mentions.replace(text, workspace)
      end

      def display_additional_lines(lines)
        remaining = lines[1..2].map(&:strip).reject(&:empty?)
        remaining.each { |line| puts "     #{truncate(line, 100)}" }
        puts "     [#{lines.length - 3} more lines...]" if lines.length > 3
      end

      def truncate(text, max_length)
        text.length > max_length ? "#{text[0..max_length]}..." : text
      end

      def format_time(slack_timestamp)
        Time.at(slack_timestamp.to_f).strftime('%b %d %-I:%M %p')
      end

      def debug_missing(item_type)
        @on_debug&.call("Could not display #{item_type} activity - missing data")
      end
    end
  end
end
