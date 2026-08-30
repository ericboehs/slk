# frozen_string_literal: true

require 'date'

module Slk
  module Models
    # Current Do Not Disturb state for one workspace, from dnd.info.
    #
    # Slack reports two independent things through that one endpoint: a manual
    # snooze ("pause notifications for 2 hours") and the configured DND
    # schedule ("quiet from 8pm to 8am"). From the outside they are the same
    # thing — messages do not notify — so `active?` covers both and `source`
    # says which one is responsible.
    DndState = Data.define(:snoozing, :snooze_endtime, :scheduled, :next_start, :next_end) do
      def self.from_api(data)
        data = {} unless data.is_a?(Hash)

        new(
          snoozing: data['snooze_enabled'] == true,
          snooze_endtime: data['snooze_endtime'].to_i,
          scheduled: data['dnd_enabled'] == true,
          next_start: data['next_dnd_start_ts'].to_i,
          next_end: data['next_dnd_end_ts'].to_i
        )
      end

      def active? = snoozing || in_scheduled_hours?

      # `next_dnd_*` names the *next* window while DND hours are off and the
      # current one while they are running, so "now falls inside it" is the
      # only reading that means notifications are being held right now.
      #
      # Slack reports 1 for both schedule timestamps when no schedule is
      # configured, so a bare `positive?` would read that as a window that
      # opened in 1970 and never closed.
      def in_scheduled_hours?
        return false unless scheduled && next_start > 1 && next_end > next_start

        now = Time.now.to_i
        next_start <= now && now < next_end
      end

      def source
        return :both if snoozing && in_scheduled_hours?
        return :snooze if snoozing
        return :schedule if in_scheduled_hours?

        nil
      end

      # The later of the two when both apply: notifications stay off until
      # every reason for holding them has expired, not the first.
      def until_time
        finishes = []
        finishes << snooze_endtime if snoozing && snooze_endtime.positive?
        finishes << next_end if in_scheduled_hours?

        finish = finishes.max
        finish ? Time.at(finish) : nil
      end

      # Same-day times need no date; an overnight schedule ending tomorrow
      # morning would otherwise read as "until 8:00am" of a day already gone.
      def until_label
        finish = until_time or return nil
        finish.to_date == Date.today ? finish.strftime('%-l:%M%P') : finish.strftime('%a %-l:%M%P')
      end

      # Empty when notifications are flowing: there is nothing to say, and a
      # "[dnd off]" on every line would bury the workspace where it is on.
      def to_s
        return '' unless active?

        label = until_label
        # A snooze with no end time is a state Slack can report; saying "[dnd]"
        # is honest about not knowing when it lifts.
        label ? "[dnd until #{label}]" : '[dnd]'
      end
    end
  end
end
