# frozen_string_literal: true

module Slk
  module Formatters
    # CSV export of a deactivation list, for the spreadsheet that inevitably
    # gets asked for. Every matched row is written, not just the screenful a
    # terminal would show — a truncated export is a wrong answer that looks
    # like a right one.
    class DeactivationCsv
      HEADERS = %w[deactivated_on user_id handle real_name title email bot].freeze
      TENURE_HEADERS = %w[started_on tenure_months tenure].freeze

      def initialize(output:, tenures: nil)
        @output = output
        @tenures = tenures
      end

      def render(records)
        @output.puts(CsvWriter.row(headers))
        records.each { |record| @output.puts(CsvWriter.row(cells(record))) }
      end

      private

      def headers
        @tenures ? HEADERS + TENURE_HEADERS : HEADERS
      end

      def cells(record)
        row = [record.date, record.user_id, record.handle, record.real_name,
               record.title, record.email, record.bot]
        @tenures ? row + tenure_cells(record) : row
      end

      # An unknown start date leaves empty cells rather than a zero: a
      # spreadsheet that averages tenure should skip the blanks, not count
      # them as people who left the day they arrived.
      def tenure_cells(record)
        tenure = @tenures[record.user_id]
        return [nil, nil, nil] unless tenure

        [tenure.started, tenure.months, tenure.to_s]
      end
    end
  end
end
