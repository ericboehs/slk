# frozen_string_literal: true

module Slk
  module Formatters
    # Formats reaction data for terminal display
    class ReactionFormatter
      def initialize(output:, emoji_replacer:, cache_store:)
        @output = output
        @emoji = emoji_replacer
        @cache = cache_store
      end

      # Format reactions inline for simple display: " [2 👍, 1 ❤️]"
      def format_inline(reactions, options = {})
        parts = reactions.map do |r|
          emoji = resolve_emoji(r.name, options)
          "#{r.count} #{emoji}"
        end
        " [#{parts.join(', ')}]"
      end

      # Format reactions as a single line: "[2 👍  1 ❤️]"
      def format_summary(reactions, options = {})
        reaction_text = reactions.map do |r|
          emoji = resolve_emoji(r.name, options)
          "#{r.count} #{emoji}"
        end.join('  ')

        @output.yellow("[#{reaction_text}]")
      end

      # Format reactions with timestamps, one per line
      def format_with_timestamps(reactions, workspace, options = {})
        workspace_name = workspace&.name
        lines = []

        reactions.each do |reaction|
          emoji = resolve_emoji(reaction.name, options)
          user_strings = format_user_timestamps(reaction, workspace_name, options)
          lines << @output.yellow("  ↳ #{emoji} #{user_strings.join(', ')}")
        end

        lines
      end

      private

      def resolve_emoji(name, options)
        if options[:no_emoji]
          ":#{name}:"
        else
          @emoji.lookup_emoji(name) || ":#{name}:"
        end
      end

      def format_user_timestamps(reaction, workspace_name, options)
        reaction.users.map do |user_id|
          username = resolve_user(user_id, workspace_name, options)
          timestamp = reaction.timestamp_for(user_id)

          if timestamp
            time_str = format_time(timestamp)
            "#{username} (#{time_str})"
          else
            username
          end
        end
      end

      def resolve_user(user_id, workspace_name, options)
        return user_id if options[:no_names]

        if workspace_name
          cached = @cache.get_user(workspace_name, user_id)
          return cached if cached
        end

        user_id
      end

      def format_time(slack_timestamp)
        time = Time.at(slack_timestamp.to_f)
        time.strftime('%-I:%M:%S %p') # e.g., "2:45:30 PM"
      end
    end
  end
end
