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

      # @return [Hash] raw response; 'statuses' (recent) and 'scheduled_statuses'
      #   (pending) are each absent when Slack omits the section
      def list(count_per_section: DEFAULT_SECTION_COUNT)
        @api.post_form(@workspace, 'users.customStatus.list',
                       { statuses_count_per_section: count_per_section.to_s })
      end

      # @return [Array<Models::ScheduledStatus>] pending statuses only
      def scheduled(count_per_section: DEFAULT_SECTION_COUNT)
        response = list(count_per_section: count_per_section)
        section = response['scheduled_statuses']
        # An absent section is a protocol change, not an empty list. Reporting
        # it as "none scheduled" would invite the user to re-create statuses
        # that still exist.
        unless section.is_a?(Array)
          raise ApiError.new('Slack returned no scheduled_statuses section; this internal endpoint may have changed. ' \
                             'Check the Slack status picker before re-scheduling.',
                             code: :missing_scheduled_section)
        end

        section.map { |item| Models::ScheduledStatus.from_api(item) }
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
        Models::ScheduledStatus.from_api(confirmed_schedule(response))
      end

      # Slack answers a delete with ok: true whether or not anything changed —
      # including for an id that never existed — so the response alone is not
      # evidence. Re-reading the list at least catches an accepted delete that
      # did not apply. It cannot distinguish "cancelled" from "was never
      # there": both leave the id absent. `unschedule` covers that case ahead
      # of time by finding the workspace that owns the id.
      #
      # @return [Array(Symbol, String, nil)] `[:cancelled, nil]`, or
      #   `[:unconfirmed, reason]` when the delete was accepted but the
      #   following read failed. Those are different things: only the second
      #   read failed, and reporting it as a failed *cancel* would send the
      #   user back to re-cancel something already gone.
      # @raise [ApiError] only when the status is demonstrably still there
      def delete_scheduled(custom_status_id)
        @api.post_form(@workspace, 'users.customStatus.deleteScheduled',
                       { custom_status_id: custom_status_id })
        confirm_deleted(custom_status_id)
      end

      private

      # The delete has already been accepted by the time this runs, so this
      # only decides how much can honestly be said about it. A read that
      # fails — including a rate-limited one, since the confirming read hits
      # the same `list` method a multi-workspace sweep just used — is a
      # failure to look, not a failure to delete.
      def confirm_deleted(custom_status_id)
        return [:cancelled, nil] unless scheduled.any? { |status| status.id == custom_status_id }

        raise ApiError.new("Slack reported success but #{custom_status_id} is still scheduled.",
                           code: :delete_not_applied)
      rescue ApiError => e
        raise if e.code == :delete_not_applied

        [:unconfirmed, e.message]
      end

      # A create that reports ok without echoing back the status it made has
      # not demonstrably created anything.
      #
      # The id check duplicates ScheduledStatus.validate!, deliberately:
      # letting an id-less payload through to that guard trades this message
      # for "Slack returned a scheduled status with no id: {}", which tells
      # the user nothing they can act on. Here the answer is the same either
      # way — go look at the picker.
      def confirmed_schedule(response)
        payload = response['scheduled_status']
        return payload if payload.is_a?(Hash) && !payload['id'].to_s.empty?

        raise ApiError.new('Slack accepted the request but returned no scheduled status, so nothing was confirmed. ' \
                           'Check the Slack status picker to see whether it was created.',
                           code: :malformed_schedule_response)
      end
    end
  end
end
