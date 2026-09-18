# frozen_string_literal: true

module Slk
  module Formatters
    # RFC 4180 CSV, hand-rolled: Ruby 3.4 moved csv out of the default gems
    # and into the bundled ones, so requiring it would make this tool depend
    # on a gem, and it ships with none.
    #
    # Quotes only the fields that need it, so the common row stays readable in
    # a terminal as well as in a spreadsheet.
    module CsvWriter
      module_function

      NEEDS_QUOTES = /[",\r\n]|\A\s|\s\z/

      def row(values)
        values.map { |value| escape(value) }.join(',')
      end

      def escape(value)
        text = stringify(value)
        return text unless NEEDS_QUOTES.match?(text)

        %("#{text.gsub('"', '""')}")
      end

      # nil is an empty cell. Writing the literal "nil" would give a
      # spreadsheet a four-character string to count, sort and average.
      def stringify(value)
        value.nil? ? '' : value.to_s
      end
    end
  end
end
