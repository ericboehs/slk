# frozen_string_literal: true

module Slk
  module Models
    # How long someone was here: a start date from their Slack profile and the
    # date their account was deactivated.
    #
    # Both ends are softer than they look. The start date is whatever an admin
    # typed into a custom profile field, and the end is the account's `updated`
    # timestamp. Neither is a payroll record, so this rounds to whole months
    # and refuses to imply a precision it does not have.
    Tenure = Data.define(:started_on, :ended_on) do
      # @param started [String, nil] ISO date from the profile field
      # @param ended [Time, nil] deactivation time
      def self.build(started, ended)
        date = parse_date(started)
        return nil unless date

        new(started_on: date, ended_on: ended ? to_date(ended) : nil)
      end

      def self.parse_date(value)
        text = value.to_s.strip
        return nil unless /\A\d{4}-\d{2}-\d{2}\z/.match?(text)

        Date.iso8601(text)
      rescue Date::Error
        nil
      end

      def self.to_date(time)
        Date.new(time.year, time.month, time.day)
      end

      # Nil when the account is still active, or when the end predates the
      # start — a start date typed in after the fact can land anywhere, and a
      # negative tenure is a data entry error, not a fact about a person.
      def months
        return nil unless ended_on && ended_on >= started_on

        ended_on.day < started_on.day ? month_span - 1 : month_span
      end

      def month_span
        ((ended_on.year - started_on.year) * 12) + (ended_on.month - started_on.month)
      end
      private :month_span

      # "6y 2mo", "11mo", "<1mo" — whole months only.
      def to_s
        total = months
        return '' unless total
        return '<1mo' if total.zero?

        years, rest = total.divmod(12)
        [years.positive? ? "#{years}y" : nil, rest.positive? ? "#{rest}mo" : nil].compact.join(' ')
      end

      # Blank for a tenure that cannot be worked out — an active account, or
      # an end date that predates the start.
      def unknown? = months.nil?

      def started = started_on.iso8601
    end
  end
end
