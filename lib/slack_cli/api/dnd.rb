# frozen_string_literal: true

module SlackCli
  module Api
    class Dnd
      def initialize(api_client, workspace)
        @api = api_client
        @workspace = workspace
      end

      def info
        @api.post(@workspace, "dnd.info")
      end

      def set_snooze(duration)
        minutes = duration.to_minutes
        @api.post(@workspace, "dnd.setSnooze", { num_minutes: minutes })
      end

      def end_snooze
        @api.post(@workspace, "dnd.endSnooze")
      end

      def snoozing?
        info["snooze_enabled"] == true
      end

      def snooze_remaining
        data = info
        return nil unless data["snooze_enabled"]

        endtime = data["snooze_endtime"]
        return nil unless endtime

        remaining = endtime - Time.now.to_i
        remaining > 0 ? Models::Duration.new(seconds: remaining) : nil
      end
    end
  end
end
