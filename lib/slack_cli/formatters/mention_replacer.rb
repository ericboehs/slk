# frozen_string_literal: true

module SlackCli
  module Formatters
    class MentionReplacer
      USER_MENTION_REGEX = /<@([UW][A-Z0-9]+)(?:\|([^>]+))?>/
      CHANNEL_MENTION_REGEX = /<#([CG][A-Z0-9]+)(?:\|([^>]+))?>/
      LINK_REGEX = /<(https?:\/\/[^|>]+)(?:\|([^>]+))?>/
      SPECIAL_MENTIONS = {
        "<!here>" => "@here",
        "<!channel>" => "@channel",
        "<!everyone>" => "@everyone"
      }.freeze

      def initialize(cache_store:, api_client: nil)
        @cache = cache_store
        @api = api_client
      end

      def replace(text, workspace)
        result = text.dup

        # Replace user mentions
        result.gsub!(USER_MENTION_REGEX) do
          user_id = ::Regexp.last_match(1)
          display_name = ::Regexp.last_match(2)

          if display_name
            "@#{display_name}"
          else
            cached = @cache.get_user(workspace.name, user_id)
            cached ? "@#{cached}" : "<@#{user_id}>"
          end
        end

        # Replace channel mentions
        result.gsub!(CHANNEL_MENTION_REGEX) do
          channel_id = ::Regexp.last_match(1)
          channel_name = ::Regexp.last_match(2)

          if channel_name
            "##{channel_name}"
          else
            cached = @cache.get_channel_name(workspace.name, channel_id)
            cached ? "##{cached}" : "<##{channel_id}>"
          end
        end

        # Replace links
        result.gsub!(LINK_REGEX) do
          url = ::Regexp.last_match(1)
          label = ::Regexp.last_match(2)
          label || url
        end

        # Replace special mentions
        SPECIAL_MENTIONS.each do |pattern, replacement|
          result.gsub!(pattern, replacement)
        end

        result
      end
    end
  end
end
