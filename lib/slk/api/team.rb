# frozen_string_literal: true

module Slk
  module Api
    # Wrapper for Slack team.* API endpoints
    class Team
      def initialize(api_client, workspace)
        @api = api_client
        @workspace = workspace
      end

      def info(team_id = nil)
        params = team_id ? { team: team_id } : {}
        @api.post_form(@workspace, 'team.info', params)
      end

      def profile_schema(visibility: nil)
        params = {}
        params[:visibility] = visibility if visibility
        @api.post_form(@workspace, 'team.profile.get', params)
      end
    end
  end
end
