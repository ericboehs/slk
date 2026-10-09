# frozen_string_literal: true

module Slk
  module Services
    # Huddle fields from a profile hash, or from a live users.info.
    #
    # users.info and users.profile.get are cached for an hour. Huddle state
    # changes in minutes, so a card must not trust the cached copy.
    module HuddleState
      EMPTY = { huddle_state: nil, huddle_channel_id: nil, huddle_call_id: nil }.freeze

      module_function

      def from(profile_data)
        data = profile_data || {}
        {
          huddle_state: blank_to_nil(data['huddle_state']),
          huddle_channel_id: blank_to_nil(data['huddle_state_channel_id']),
          huddle_call_id: blank_to_nil(data['huddle_state_call_id']),
          huddle_channel: nil
        }
      end

      def apply(profile, users_api, user_id, on_debug: nil)
        Models::Profile.new(**profile.to_h, **read(users_api, user_id, on_debug: on_debug))
      end

      def read(users_api, user_id, on_debug: nil)
        from(users_api.info(user_id).dig('user', 'profile'))
      rescue ApiError => e
        on_debug&.call("huddle state for #{user_id} failed: #{e.message}")
        EMPTY.merge(huddle_channel: nil)
      end

      def blank_to_nil(value)
        text = value.to_s
        text.empty? ? nil : text
      end
    end
  end
end
