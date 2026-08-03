# frozen_string_literal: true

module Slk
  module Models
    # A status queued to turn on later, from users.customStatus.list.
    #
    # Slack derives `duration` server-side from the window, so it is not
    # modelled here — the window itself is the source of truth.
    ScheduledStatus = Data.define(:id, :text, :emoji, :date_scheduled, :date_expire, :dnd, :active) do
      def self.from_api(data)
        validate!(data)

        new(
          id: data['id'].to_s,
          text: data['text'].to_s,
          emoji: data['emoji'].to_s,
          date_scheduled: data['date_scheduled'].to_i,
          date_expire: data['date_expire'].to_i,
          dnd: truthy?(data['is_dnd']),
          active: truthy?(data['is_active'])
        )
      end

      # Every field is coerced, so without this guard any payload at all —
      # a bare string, nil, a hash of unexpected keys — becomes a valid-looking
      # record with an empty id that prints as a blank line and never matches
      # the id the user asked about. An unusable record is a protocol change,
      # not a status.
      def self.validate!(data)
        return if data.is_a?(Hash) && !data['id'].to_s.empty?

        raise ApiError.new("Slack returned a scheduled status with no id: #{data.inspect[0, 120]}",
                           code: :malformed_scheduled_status)
      end
      private_class_method :validate!

      # These endpoints are string-typed on the way in — Api::CustomStatus sends
      # is_dnd as 'true' — so a strict `== true` would quietly read a scheduled
      # DND back as off. Accept the shapes Slack actually uses.
      def self.truthy?(value) = [true, 'true', 1, '1'].include?(value)
      private_class_method :truthy?

      def starts_at = date_scheduled.positive? ? Time.at(date_scheduled) : nil
      def ends_at = date_expire.positive? ? Time.at(date_expire) : nil

      def to_s
        span = window
        [
          emoji,
          text,
          span.empty? ? '' : "(#{span})",
          ('[dnd]' if dnd),
          # Slack marks the one that has already turned on. Worth showing: it
          # is the difference between "will happen" and "is happening".
          ('[active]' if active)
        ].reject { |part| part.to_s.empty? }.join(' ')
      end

      # Human-readable window; the end date is only repeated when it differs
      # from the start date, which makes multi-day windows obvious.
      def window
        dated = '%a %b %-d %-l:%M%P'
        start_time = starts_at or return ''
        formatted = start_time.strftime(dated)
        finish = ends_at or return formatted

        "#{formatted} -> #{finish.strftime(same_day?(start_time, finish) ? '%-l:%M%P' : dated)}"
      end

      private

      def same_day?(start_time, finish)
        start_time.to_date == finish.to_date
      end
    end
  end
end
