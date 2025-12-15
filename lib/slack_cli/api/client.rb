# frozen_string_literal: true

module SlackCli
  module Api
    class Client
      def initialize(api_client, workspace)
        @api = api_client
        @workspace = workspace
      end

      def counts
        @api.post(@workspace, "client.counts")
      end

      def unread_channels
        response = counts
        channels = response.dig("channels") || []

        channels.select { |ch| (ch["mention_count"] || 0) > 0 || ch["has_unreads"] }
      end

      def unread_dms
        response = counts
        dms = response.dig("ims") || []
        mpims = response.dig("mpims") || []

        (dms + mpims).select { |dm| (dm["mention_count"] || 0) > 0 || dm["has_unreads"] }
      end

      def total_unread_count
        response = counts

        channel_count = (response.dig("channels") || []).sum { |c| c["mention_count"] || 0 }
        dm_count = (response.dig("ims") || []).sum { |d| d["dm_count"] || 0 }
        mpim_count = (response.dig("mpims") || []).sum { |m| m["mention_count"] || 0 }

        channel_count + dm_count + mpim_count
      end
    end
  end
end
