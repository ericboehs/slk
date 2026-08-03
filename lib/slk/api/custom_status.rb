# frozen_string_literal: true

module Slk
  module Api
    # Wrapper for Slack's internal users.customStatus.* endpoints, which back
    # the "Scheduled" section of the status picker.
    #
    # Two undocumented quirks these methods paper over:
    #   - Only form-encoded bodies are accepted. A JSON body is ignored and the
    #     call fails with invalid_arguments naming every field as missing.
    #   - list omits scheduled_statuses entirely unless
    #     statuses_count_per_section is passed.
    class CustomStatus
      DEFAULT_SECTION_COUNT = 20

      def initialize(api_client, workspace)
        @api = api_client
        @workspace = workspace
      end

      # @return [Hash] raw response with 'statuses' (recent) and
      #   'scheduled_statuses' (pending) keys
      def list(count_per_section: DEFAULT_SECTION_COUNT)
        @api.post_form(@workspace, 'users.customStatus.list',
                       { statuses_count_per_section: count_per_section.to_s })
      end

      # @return [Array<Models::ScheduledStatus>] pending statuses only
      def scheduled(count_per_section: DEFAULT_SECTION_COUNT)
        response = list(count_per_section: count_per_section)
        (response['scheduled_statuses'] || []).map { |item| Models::ScheduledStatus.from_api(item) }
      end

      # @param date_scheduled [Integer] Unix timestamp the status turns on
      # @param date_expire [Integer, nil] Unix timestamp it clears
      # @param dnd [Boolean] also pause notifications while active
      # @return [Models::ScheduledStatus]
      def schedule(text:, emoji:, date_scheduled:, date_expire: nil, dnd: false)
        params = { text: text, emoji: emoji, date_scheduled: date_scheduled.to_i.to_s }
        params[:date_expire] = date_expire.to_i.to_s if date_expire
        params[:is_dnd] = 'true' if dnd

        response = @api.post_form(@workspace, 'users.customStatus.schedule', params)
        Models::ScheduledStatus.from_api(response['scheduled_status'])
      end

      def delete_scheduled(custom_status_id)
        @api.post_form(@workspace, 'users.customStatus.deleteScheduled',
                       { custom_status_id: custom_status_id })
      end
    end
  end
end
