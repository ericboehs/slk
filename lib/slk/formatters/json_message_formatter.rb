# frozen_string_literal: true

module Slk
  module Formatters
    # Formats Slack messages as JSON for structured output
    class JsonMessageFormatter
      def initialize(cache_store:)
        @cache = cache_store
      end

      # Format a message as a JSON-serializable hash
      def format(message, workspace: nil, options: {})
        result = build_base_result(message)
        result[:reactions] = format_reactions(message.reactions, workspace, options)

        add_user_name(result, message, workspace, options)
        add_channel_info(result, workspace, options)

        result
      end

      private

      def build_base_result(message)
        {
          ts: message.ts,
          user_id: message.user_id,
          text: message.text,
          reply_count: message.reply_count,
          thread_ts: message.thread_ts,
          attachments: message.attachments,
          files: message.files
        }
      end

      def format_reactions(reactions, workspace, options)
        reactions.map do |r|
          reaction_hash = { name: r.name, count: r.count }
          reaction_hash[:users] = format_reaction_users(r, workspace, options)
          reaction_hash
        end
      end

      def format_reaction_users(reaction, workspace, options)
        workspace_name = workspace&.name

        reaction.users.map do |user_id|
          user_hash = { id: user_id }
          add_user_reaction_name(user_hash, user_id, workspace_name, options)
          add_user_reaction_timestamp(user_hash, reaction, user_id)
          user_hash
        end
      end

      def add_user_reaction_name(user_hash, user_id, workspace_name, options)
        return if options[:no_names]
        return unless workspace_name

        cached_name = @cache.get_user(workspace_name, user_id)
        user_hash[:name] = cached_name if cached_name
      end

      def add_user_reaction_timestamp(user_hash, reaction, user_id)
        return unless reaction.timestamps?

        timestamp = reaction.timestamp_for(user_id)
        return unless timestamp

        user_hash[:reacted_at] = timestamp
        user_hash[:reacted_at_iso8601] = Time.at(timestamp.to_f).iso8601
      end

      def add_user_name(result, message, workspace, options)
        return if options[:no_names]

        workspace_name = workspace&.name
        return unless workspace_name

        user_name = @cache.get_user(workspace_name, message.user_id)
        result[:user_name] = user_name if user_name
      end

      def add_channel_info(result, workspace, options)
        return unless options[:channel_id]

        result[:channel_id] = options[:channel_id]
        workspace_name = workspace&.name
        return unless workspace_name

        channel_name = @cache.get_channel_name(workspace_name, options[:channel_id])
        result[:channel_name] = channel_name if channel_name
      end
    end
  end
end
