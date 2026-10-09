# frozen_string_literal: true

module Slk
  module Services
    # Turns a huddle channel id into a display label. A failed lookup is not
    # a failed command: private channels and DMs the token cannot see still
    # belong in the list, just without a name.
    class HuddleChannelLabel
      def initialize(runner:, cache_store:, on_debug: nil)
        @runner = runner
        @cache = cache_store
        @on_debug = on_debug
      end

      def label(workspace, channel_id)
        return nil if channel_id.to_s.empty?

        cached_label(workspace, channel_id) || fetch_label(workspace, channel_id)
      end

      private

      def cached_label(workspace, channel_id)
        name = @cache.get_channel_name(workspace.name, channel_id)
        "##{name}" if name
      end

      def fetch_label(workspace, channel_id)
        label_from(workspace, channel_id, channel_info(workspace, channel_id))
      rescue ApiError => e
        @on_debug&.call("Channel lookup failed for #{channel_id}: #{e.message}")
        nil
      end

      def channel_info(workspace, channel_id)
        @runner.conversations_api(workspace.name).info(channel: channel_id)['channel'] || {}
      end

      def label_from(workspace, channel_id, channel)
        return 'DM' if channel['is_im']
        return 'group DM' if channel['is_mpim']

        named_label(workspace, channel_id, channel['name'])
      end

      def named_label(workspace, channel_id, name)
        return nil if name.to_s.empty?

        @cache.set_channel(workspace.name, name, channel_id)
        "##{name}"
      end
    end
  end
end
