# frozen_string_literal: true

module Slk
  module Services
    # Fills in what a profile no longer says about a huddle.
    #
    # Slack stopped sending huddle_state_channel_id; profiles carry only the
    # state and the call id. huddles.get maps the call id to its channel and
    # the full participant list, which includes Slack Connect guests who are
    # missing from users.list. A huddle the token cannot see is left as is.
    class HuddleRoom
      Room = Data.define(:channel_id, :participant_ids)

      def initialize(api_client:, workspace:, on_debug: nil)
        @api = Api::Huddles.new(api_client, workspace)
        @on_debug = on_debug
      end

      # @return [Room, nil]
      def lookup(call_id)
        return nil if call_id.to_s.empty?

        room = @api.get(call_id)
        return nil if room.empty? || room['has_ended']

        Room.new(channel_id: single_channel(room), participant_ids: Array(room['participants']))
      rescue ApiError => e
        @on_debug&.call("huddles.get #{call_id} failed: #{e.message}")
        nil
      end

      # A profile's channel id if Slack sent one, else the room's.
      def channel_for(profile)
        return profile.huddle_channel_id unless profile.huddle_channel_id.to_s.empty?

        lookup(profile.huddle_call_id)&.channel_id
      end

      private

      def single_channel(room)
        channels = Array(room['channels']).reject { |id| id.to_s.empty? }.uniq
        channels.first if channels.one?
      end
    end
  end
end
