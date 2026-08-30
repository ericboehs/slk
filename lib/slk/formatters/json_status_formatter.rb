# frozen_string_literal: true

require 'time'

module Slk
  module Formatters
    # Renders `slk status` snapshots as JSON for scripts and statuslines.
    #
    # Two shape rules the consumers depend on:
    #
    #   - Always an array, one entry per workspace, even for a single one. The
    #     workspace set changes with -w/--all, and a document whose shape
    #     changes with a flag cannot be parsed by a script that did not pass it.
    #   - null means "not checked" (skipped, or the lookup failed); an empty
    #     array or false means checked. A statusline that treats a failed DND
    #     lookup as "DND off" would quietly say the opposite of the truth.
    #
    # Timestamps appear twice: the raw Slack epoch under Slack's own field name
    # and an ISO 8601 string beside it, so neither jq nor the shell has to do
    # date arithmetic to print "until 3:00pm".
    class JsonStatusFormatter
      def format(snapshots)
        snapshots.map { |snapshot| snapshot_hash(snapshot) }
      end

      # `slk status scheduled --json`: the same array, narrowed to the part
      # that command is about, so a script can read either with one shape.
      #
      # @param by_workspace [Hash{String => Array<Models::ScheduledStatus>, nil}]
      def format_scheduled(by_workspace)
        by_workspace.map do |name, scheduled|
          { workspace: name, scheduled: scheduled&.map { |status| scheduled_hash(status) } }
        end
      end

      private

      def snapshot_hash(snapshot)
        {
          workspace: snapshot.workspace_name,
          status: status_hash(snapshot.status),
          presence: presence_hash(snapshot.presence),
          dnd: dnd_hash(snapshot.dnd),
          scheduled: snapshot.scheduled&.map { |status| scheduled_hash(status) }
        }
      end

      def status_hash(status)
        {
          text: status.text,
          emoji: status.emoji,
          # Slack's own 0-for-never, kept as-is; `expires_at` is the readable
          # form and is null rather than "1970-01-01" when there is no expiry.
          expiration: status.expiration,
          expires_at: iso8601(status.expiration_time),
          empty: status.empty?
        }
      end

      def presence_hash(presence)
        return nil unless presence

        { presence: presence[:presence], manual_away: presence[:manual_away], online: presence[:online] }
      end

      def dnd_hash(dnd)
        return nil unless dnd

        {
          active: dnd.active?,
          source: dnd.source&.to_s,
          snoozing: dnd.snoozing,
          in_scheduled_hours: dnd.in_scheduled_hours?,
          until: dnd.until_time&.to_i,
          until_at: iso8601(dnd.until_time)
        }
      end

      # Slack's own field names and epochs, plus a readable form of each
      # timestamp. `slice` rather than the whole record on purpose: this is a
      # published shape, and a field added to the model later should not join
      # it without someone deciding to.
      def scheduled_hash(status)
        status.to_h.slice(:id, :text, :emoji, :date_scheduled, :date_expire, :dnd, :active)
              .merge(starts_at: iso8601(status.starts_at), ends_at: iso8601(status.ends_at))
      end

      def iso8601(time) = time&.iso8601
    end
  end
end
