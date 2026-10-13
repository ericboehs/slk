# frozen_string_literal: true

module Slk
  module Support
    # Group DMs can be given a name in Slack ("named chats"). They are still
    # mpims, but `name` holds what the user typed ("ifams review") rather
    # than the generated mpdm-alice--bob-1 slug. conversations.info flags them
    # with properties.has_custom_mpdm_name; search.messages sends no
    # properties, so a name that isn't an mpdm-* slug counts as custom too.
    module GroupDmName
      SLUG = /\Ampdm-/

      module_function

      # @param channel [Hash] conversation payload from Slack
      # @return [String, nil] the custom name, or nil for anything else
      def custom(channel)
        return nil unless channel.is_a?(Hash) && channel['is_mpim']

        name = channel['name'].to_s
        return nil if name.empty?
        return name if channel.dig('properties', 'has_custom_mpdm_name')

        custom_name?(name) ? name : nil
      end

      # @param name [String, nil] a group DM's Slack name
      # @return [Boolean] true when the name was set by a person
      def custom_name?(name)
        !name.to_s.empty? && !name.to_s.match?(SLUG)
      end

      # @return [String, nil] "#name" for a named group DM, else nil
      def label(name)
        "##{name}" if custom_name?(name)
      end
    end
  end
end
