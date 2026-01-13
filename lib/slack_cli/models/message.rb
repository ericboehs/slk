# frozen_string_literal: true

module SlackCli
  module Models
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
      # Minimum text length before we extract content from Block Kit blocks.
      # Slack sometimes sends minimal text (like a link preview) with the full
      # content in blocks. 20 chars catches most of these cases without
      # unnecessarily processing blocks for normal messages.
      BLOCK_TEXT_THRESHOLD = 20

      def self.from_api(data, channel_id: nil)
        text = data["text"] || ""
        blocks = data["blocks"] || []

        # Extract text from Block Kit blocks if text is empty or minimal
        if text.length < BLOCK_TEXT_THRESHOLD
          blocks_text = extract_block_text(blocks)
          text = blocks_text unless blocks_text.empty?
        end

        new(
          ts: data["ts"],
          user_id: data["user"] || data["bot_id"] || data["username"],
          text: text,
          reactions: (data["reactions"] || []).map { |r| Reaction.from_api(r) },
          reply_count: data["reply_count"] || 0,
          thread_ts: data["thread_ts"],
          files: data["files"] || [],
          attachments: data["attachments"] || [],
          blocks: blocks,
          user_profile: data["user_profile"],
          bot_profile: data["bot_profile"],
          username: data["username"],
          subtype: data["subtype"],
          channel_id: channel_id
        )
      end

      def self.extract_block_text(blocks)
        return "" unless blocks.is_a?(Array)

        blocks.filter_map do |block|
          case block["type"]
          when "section"
            block.dig("text", "text")
          when "rich_text"
            extract_rich_text_content(block["elements"])
          end
        end.join("\n")
      end

      def self.extract_rich_text_content(elements)
        return "" unless elements.is_a?(Array)

        elements.filter_map do |element|
          next unless element["elements"].is_a?(Array)

          element["elements"].filter_map do |item|
            item["text"] if item["type"] == "text"
          end.join
        end.join
      end

      def initialize(
        ts:,
        user_id:,
        text: "",
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
        ts_str = ts.to_s.strip
        user_id_str = user_id.to_s.strip

        raise ArgumentError, "ts cannot be empty" if ts_str.empty?
        raise ArgumentError, "user_id cannot be empty" if user_id_str.empty?

        super(
          ts: ts_str.freeze,
          user_id: user_id_str.freeze,
          text: text.to_s.freeze,
          reactions: reactions.freeze,
          reply_count: reply_count.to_i,
          thread_ts: thread_ts&.freeze,
          files: deep_freeze(files),
          attachments: deep_freeze(attachments),
          blocks: deep_freeze(blocks),
          user_profile: deep_freeze(user_profile),
          bot_profile: deep_freeze(bot_profile),
          username: username&.freeze,
          subtype: subtype&.freeze,
          channel_id: channel_id&.freeze
        )
      end

      # Recursively freeze nested structures (arrays and hashes)
      def self.deep_freeze(obj)
        case obj
        when Hash
          obj.each_value { |v| deep_freeze(v) }
          obj.freeze
        when Array
          obj.each { |v| deep_freeze(v) }
          obj.freeze
        else
          obj.freeze if obj.respond_to?(:freeze)
        end
        obj
      end

      private_class_method :deep_freeze

      # Instance method delegate to class method for use in initialize
      def deep_freeze(obj)
        self.class.send(:deep_freeze, obj)
      end

      def timestamp
        Time.at(ts.to_f)
      end

      def has_thread?
        reply_count > 0
      end

      def is_reply?
        thread_ts && thread_ts != ts
      end

      def has_reactions?
        !reactions.empty?
      end

      def has_files?
        !files.empty?
      end

      def has_blocks?
        !blocks.empty?
      end

      def embedded_username
        # Try user_profile first (regular users)
        if user_profile
          display = user_profile["display_name"]
          real = user_profile["real_name"]

          return display unless display.to_s.empty?
          return real unless real.to_s.empty?
        end

        # Try bot_profile (bot messages)
        if bot_profile
          name = bot_profile["name"]
          return name unless name.to_s.empty?
        end

        # Fall back to username field (some bots/integrations)
        return username unless username.to_s.empty?

        nil
      end

      def bot?
        user_id.start_with?("B") || subtype == "bot_message"
      end

      def system_message?
        %w[channel_join channel_leave channel_topic channel_purpose].include?(subtype)
      end

      # Create a copy of this message with updated reactions
      def with_reactions(new_reactions)
        Message.new(
          ts: ts,
          user_id: user_id,
          text: text,
          reactions: new_reactions,
          reply_count: reply_count,
          thread_ts: thread_ts,
          files: files,
          attachments: attachments,
          blocks: blocks,
          user_profile: user_profile,
          bot_profile: bot_profile,
          username: username,
          subtype: subtype,
          channel_id: channel_id
        )
      end
    end
  end
end
