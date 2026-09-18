# frozen_string_literal: true

module Slk
  module Formatters
    # Renders deactivation lists and per-month histograms.
    class DeactivationFormatter
      DATE_WIDTH = 10
      MAX_NAME_WIDTH = 26
      MIN_TITLE_WIDTH = 12
      MAX_BAR_WIDTH = 48
      BAR_CHARS = '█'

      def initialize(output:, width: nil)
        @output = output
        @width = width || 100
      end

      # One line per departure: date, name, tenure, title. Full ISO dates on
      # every row (rather than month headings) so the output stays greppable.
      #
      # `tenures` is keyed by user ID and may cover only some of the rows: a
      # start date nobody filled in leaves the column blank rather than
      # guessing, and the column disappears entirely when none are known.
      def list(records, tenures: {})
        name_width = name_column_width(records)
        tenure_width = tenure_column_width(records, tenures)
        records.each { |record| @output.puts(row(record, name_width, tenures, tenure_width)) }
      end

      def chart(records, from: nil, to: nil)
        counts = monthly_counts(records, from: from, to: to)
        return if counts.empty?

        peak = counts.values.max
        label_width = counts.values.map { |n| n.to_s.length }.max
        counts.each { |month, count| @output.puts(chart_row(month, count, peak, label_width)) }
      end

      def summary(text)
        @output.puts(@output.bold(text))
      end

      def note(text)
        @output.puts(@output.gray(text))
      end

      # Deactivations per calendar month, oldest first, with empty months
      # filled in — a gap in a histogram should read as zero, not as absence.
      # `from`/`to` widen the span to the window the caller asked about, so a
      # quiet first or last month is shown as quiet rather than dropped.
      def monthly_counts(records, from: nil, to: nil)
        months = records.filter_map(&:month).sort
        first = [from, months.first].compact.min
        last = [to, months.last].compact.max
        return {} if first.nil? || last.nil? || first > last

        all_months(first, last).to_h do |month|
          [month, months.count(month)]
        end
      end

      private

      def chart_row(month, count, peak, label_width)
        bar = BAR_CHARS * bar_length(count, peak)
        "#{@output.gray(month)}  #{count.to_s.rjust(label_width)}  #{bar}".rstrip
      end

      def row(record, name_width, tenures = {}, tenure_width = 0)
        line = "#{@output.gray((record.date || 'unknown').ljust(DATE_WIDTH))}  " \
               "#{truncate(record.best_name.to_s, name_width).ljust(name_width)}"
        line = "#{line}  #{@output.gray(tenure_cell(record, tenures, tenure_width))}" if tenure_width.positive?
        title = truncate(record.title.to_s, title_width(name_width, tenure_width))
        title.empty? ? line : "#{line}  #{@output.gray(title)}"
      end

      def tenure_cell(record, tenures, width)
        tenures[record.user_id].to_s.rjust(width)
      end

      def tenure_column_width(records, tenures)
        return 0 if tenures.nil? || tenures.empty?

        records.filter_map { |r| tenures[r.user_id]&.to_s&.length }.max || 0
      end

      def name_column_width(records)
        longest = records.map { |r| r.best_name.to_s.length }.max || 0
        longest.clamp(8, MAX_NAME_WIDTH)
      end

      def title_width(name_width, tenure_width = 0)
        tenure_space = tenure_width.positive? ? tenure_width + 2 : 0
        [@width - DATE_WIDTH - name_width - tenure_space - 4, MIN_TITLE_WIDTH].max
      end

      # A month nobody left gets no bar at all. Rounding a zero up to one
      # block would draw departures that did not happen.
      def bar_length(count, peak)
        return 0 if peak.zero? || count.zero?

        available = (@width - 16).clamp(10, MAX_BAR_WIDTH)
        [((count.to_f / peak) * available).round, 1].max
      end

      def truncate(text, width)
        return text if text.length <= width

        "#{text[0, width - 1]}…"
      end

      def all_months(first, last)
        (month_index(first)..month_index(last)).map do |index|
          format('%<year>04d-%<month>02d', year: index / 12, month: (index % 12) + 1)
        end
      end

      def month_index(month)
        year, mon = month.split('-').map(&:to_i)
        (year * 12) + (mon - 1)
      end
    end
  end
end
