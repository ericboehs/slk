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
        return nil unless user_profile

        display = user_profile["display_name"]
        real = user_profile["real_name"]

        return display unless display.to_s.empty?
        return real unless real.to_s.empty?

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
