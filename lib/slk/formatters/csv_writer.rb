# frozen_string_literal: true

module Slk
  module Formatters
    # RFC 4180 CSV, hand-rolled: Ruby's csv library left the default gems in
    # 3.4, and this tool ships with no dependencies.
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

      # nil is an empty cell, not the word "nil" — a spreadsheet reading
      # "unknown" as a value would count it as data.
      def stringify(value)
        value.nil? ? '' : value.to_s
      end
    end
  end
end
