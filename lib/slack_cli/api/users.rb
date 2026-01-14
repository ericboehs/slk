# frozen_string_literal: true

module SlackCli
  module Api
    # Wrapper for Slack users.* API endpoints
    class Users
      def initialize(api_client, workspace, on_debug: nil)
        @api = api_client
        @workspace = workspace
        @on_debug = on_debug
      end

      def get_profile
        response = @api.post(@workspace, 'users.profile.get')
        response['profile']
      end

      def get_status
        profile = get_profile
        Models::Status.new(
          text: profile['status_text'] || '',
          emoji: profile['status_emoji'] || '',
          expiration: profile['status_expiration'] || 0
        )
      end

      def set_status(text:, emoji: nil, duration: nil)
        expiration = duration&.to_expiration || 0

        @api.post(@workspace, 'users.profile.set', {
                    profile: {
                      status_text: text,
                      status_emoji: emoji || '',
                      status_expiration: expiration
                    }
                  })
      end

      def clear_status
        set_status(text: '', emoji: '', duration: nil)
      end

      def get_presence
        response = @api.post(@workspace, 'users.getPresence')
        {
          presence: response['presence'],
          manual_away: response['manual_away'],
          online: response['online']
        }
      end

      def set_presence(presence)
        @api.post(@workspace, 'users.setPresence', { presence: presence })
      end

      def list(cursor: nil, limit: 1000)
        params = { limit: limit }
        params[:cursor] = cursor if cursor
        @api.post(@workspace, 'users.list', params)
      end

      def info(user_id)
        @api.post_form(@workspace, 'users.info', { user: user_id })
      end

      def get_prefs
        @api.post(@workspace, 'users.prefs.get')
      end

      def muted_channels
        prefs = get_prefs

        # First try the legacy muted_channels format (comma-separated string)
        muted = prefs.dig('prefs', 'muted_channels')
        return muted.split(',').reject(&:empty?) if muted.is_a?(String) && !muted.empty?

        # New format: muted channels are in all_notifications_prefs JSON string
        # Structure: {"channels": {"C123": {"muted": true}, ...}}
        notifications_prefs = prefs.dig('prefs', 'all_notifications_prefs')
        if notifications_prefs.is_a?(String) && !notifications_prefs.empty?
          begin
            parsed = JSON.parse(notifications_prefs)
            channels = parsed['channels'] || {}
            return channels.select { |_id, opts| opts['muted'] == true }.keys
          rescue JSON::ParserError => e
            @on_debug&.call("Failed to parse notification prefs: #{e.message}")
          end
        end

        []
      end

      def conversations(cursor: nil, limit: 1000)
        params = { limit: limit, types: 'public_channel,private_channel,mpim,im' }
        params[:cursor] = cursor if cursor
        @api.post_form(@workspace, 'users.conversations', params)
      end
    end
  end
end
