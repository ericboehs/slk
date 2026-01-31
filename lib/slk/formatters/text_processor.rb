# frozen_string_literal: true

module Slk
  module Formatters
    # Centralized text processing for message display
    # Handles HTML entity decoding, mention replacement, and emoji replacement
    class TextProcessor
      def initialize(mention_replacer:, emoji_replacer:)
        @mentions = mention_replacer
        @emoji = emoji_replacer
      end

      # Process raw Slack message text for display
      # @param text [String] Raw message text from Slack API
      # @param workspace [Models::Workspace] The workspace for name resolution
      # @param options [Hash] Processing options
      # @option options [Boolean] :no_emoji Skip emoji replacement
      # @option options [Boolean] :no_mentions Skip mention replacement
      # @return [String] Processed text ready for display
      def process(text, workspace, options = {})
        return '[No text]' if text.to_s.empty?

        result = decode_html_entities(text.dup)
        result = safe_replace_mentions(result, workspace) unless options[:no_mentions]
        result = safe_replace_emoji(result, workspace) unless options[:no_emoji]
        result
      end

      private

      def decode_html_entities(text)
        text.gsub('&amp;', '&').gsub('&lt;', '<').gsub('&gt;', '>')
      end

      def safe_replace_mentions(text, workspace)
        @mentions.replace(text, workspace)
      rescue StandardError
        text
      end

      def safe_replace_emoji(text, workspace)
        @emoji.replace(text, workspace)
      rescue StandardError
        text
      end
    end
  end
end
