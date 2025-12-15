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
      :user_profile,
      :bot_profile,
      :username,
      :subtype
    ) do
      def self.from_api(data)
        new(
          ts: data["ts"],
          user_id: data["user"] || data["bot_id"] || data["username"],
          text: data["text"] || "",
          reactions: (data["reactions"] || []).map { |r| Reaction.from_api(r) },
          reply_count: data["reply_count"] || 0,
          thread_ts: data["thread_ts"],
          files: data["files"] || [],
          attachments: data["attachments"] || [],
          user_profile: data["user_profile"],
          bot_profile: data["bot_profile"],
          username: data["username"],
          subtype: data["subtype"]
        )
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
        user_profile: nil,
        bot_profile: nil,
        username: nil,
        subtype: nil
      )
        super(
          ts: ts.to_s.freeze,
          user_id: user_id.to_s.freeze,
          text: text.to_s.freeze,
          reactions: reactions.freeze,
          reply_count: reply_count.to_i,
          thread_ts: thread_ts&.freeze,
          files: files.freeze,
          attachments: attachments.freeze,
          user_profile: user_profile&.freeze,
          bot_profile: bot_profile&.freeze,
          username: username&.freeze,
          subtype: subtype&.freeze
        )
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
    end
  end
end
