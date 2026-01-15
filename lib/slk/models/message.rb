# frozen_string_literal: true

# rubocop:disable Metrics/ModuleLength
module Slk
  module Models
    # Minimum text length before we extract content from Block Kit blocks.
    # Slack sometimes sends minimal text (like a link preview) with the full
    # content in blocks. 20 chars catches most of these cases without
    # unnecessarily processing blocks for normal messages.
    MESSAGE_BLOCK_TEXT_THRESHOLD = 20

    Message = Data.define(
      :ts,
      :user_id,
      :text,
      :reactions,
      :reply_count,
      :thread_ts,
      :files,
      :attachments,
      :blocks,
      :user_profile,
      :bot_profile,
      :username,
      :subtype,
      :channel_id
    ) do
      def self.from_api(data, channel_id: nil)
        text = extract_message_text(data)
        new(**build_attributes(data, text, channel_id))
      end

      def self.extract_message_text(data)
        text = data['text'] || ''
        blocks = data['blocks'] || []

        return text if text.length >= MESSAGE_BLOCK_TEXT_THRESHOLD

        blocks_text = extract_block_text(blocks)
        blocks_text.empty? ? text : blocks_text
      end

      # rubocop:disable Metrics/MethodLength
      def self.build_attributes(data, text, channel_id)
        {
          ts: data['ts'],
          user_id: data['user'] || data['bot_id'] || data['username'],
          text: text,
          reactions: parse_reactions(data['reactions']),
          reply_count: data['reply_count'] || 0,
          thread_ts: data['thread_ts'],
          files: data['files'] || [],
          attachments: data['attachments'] || [],
          blocks: data['blocks'] || [],
          user_profile: data['user_profile'],
          bot_profile: data['bot_profile'],
          username: data['username'],
          subtype: data['subtype'],
          channel_id: channel_id
        }
      end
      # rubocop:enable Metrics/MethodLength

      def self.parse_reactions(reactions_data)
        (reactions_data || []).map { |r| Reaction.from_api(r) }
      end

      def self.extract_block_text(blocks)
        return '' unless blocks.is_a?(Array)

        blocks.filter_map do |block|
          case block['type']
          when 'section'
            block.dig('text', 'text')
          when 'rich_text'
            extract_rich_text_content(block['elements'])
          end
        end.join("\n")
      end

      def self.extract_rich_text_content(elements)
        return '' unless elements.is_a?(Array)

        elements.filter_map do |element|
          next unless element['elements'].is_a?(Array)

          element['elements'].filter_map do |item|
            item['text'] if item['type'] == 'text'
          end.join
        end.join
      end

      # rubocop:disable Metrics/ParameterLists, Naming/MethodParameterName
      def initialize(
        ts:,
        user_id:,
        text: '',
        reactions: [],
        reply_count: 0,
        thread_ts: nil,
        files: [],
        attachments: [],
        blocks: [],
        user_profile: nil,
        bot_profile: nil,
        username: nil,
        subtype: nil,
        channel_id: nil
      )
        validate_required_fields!(ts, user_id)
        super(**freeze_attributes(
          ts: ts, user_id: user_id, text: text, reactions: reactions,
          reply_count: reply_count, thread_ts: thread_ts, files: files,
          attachments: attachments, blocks: blocks, user_profile: user_profile,
          bot_profile: bot_profile, username: username, subtype: subtype, channel_id: channel_id
        ))
      end
      # rubocop:enable Metrics/ParameterLists, Naming/MethodParameterName

      def validate_required_fields!(timestamp, user)
        ts_str = timestamp.to_s.strip
        user_id_str = user.to_s.strip

        raise ArgumentError, 'ts cannot be empty' if ts_str.empty?
        raise ArgumentError, 'user_id cannot be empty' if user_id_str.empty?
      end

      # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
      def freeze_attributes(attrs)
        {
          ts: attrs[:ts].to_s.strip.freeze,
          user_id: attrs[:user_id].to_s.strip.freeze,
          text: attrs[:text].to_s.freeze,
          reactions: attrs[:reactions].freeze,
          reply_count: attrs[:reply_count].to_i,
          thread_ts: attrs[:thread_ts]&.freeze,
          files: deep_freeze(attrs[:files]),
          attachments: deep_freeze(attrs[:attachments]),
          blocks: deep_freeze(attrs[:blocks]),
          user_profile: deep_freeze(attrs[:user_profile]),
          bot_profile: deep_freeze(attrs[:bot_profile]),
          username: attrs[:username]&.freeze,
          subtype: attrs[:subtype]&.freeze,
          channel_id: attrs[:channel_id]&.freeze
        }
      end
      # rubocop:enable Metrics/MethodLength, Metrics/AbcSize

      # Recursively freeze nested structures (arrays and hashes)
      def self.deep_freeze(obj)
        case obj
        when Hash then freeze_hash(obj)
        when Array then freeze_array(obj)
        else obj.freeze if obj.respond_to?(:freeze)
        end
        obj
      end

      def self.freeze_hash(hash)
        hash.each_value { |v| deep_freeze(v) }
        hash.freeze
      end

      def self.freeze_array(array)
        array.each { |v| deep_freeze(v) }
        array.freeze
      end

      private_class_method :deep_freeze, :freeze_hash, :freeze_array

      # Instance method delegate to class method for use in initialize
      def deep_freeze(obj)
        self.class.send(:deep_freeze, obj)
      end

      def timestamp
        Time.at(ts.to_f)
      end

      def thread?
        reply_count.positive?
      end

      def reply?
        thread_ts && thread_ts != ts
      end

      def reactions?
        !reactions.empty?
      end

      def files?
        !files.empty?
      end

      def blocks?
        !blocks.empty?
      end

      def embedded_username
        username_from_user_profile || username_from_bot_profile || fallback_username
      end

      def username_from_user_profile
        return nil unless user_profile

        display = user_profile['display_name']
        return display unless display.to_s.empty?

        real = user_profile['real_name']
        return real unless real.to_s.empty?

        nil
      end

      def username_from_bot_profile
        return nil unless bot_profile

        name = bot_profile['name']
        name.to_s.empty? ? nil : name
      end

      def fallback_username
        username.to_s.empty? ? nil : username
      end

      def bot?
        user_id.start_with?('B') || subtype == 'bot_message'
      end

      def system_message?
        %w[channel_join channel_leave channel_topic channel_purpose].include?(subtype)
      end

      # Create a copy of this message with updated reactions
      def with_reactions(new_reactions)
        Message.new(**to_h, reactions: new_reactions)
      end
    end
  end
end
# rubocop:enable Metrics/ModuleLength
