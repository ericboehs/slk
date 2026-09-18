# frozen_string_literal: true

require 'test_helper'

class DeactivationFormatterTest < Minitest::Test
  def setup
    @output = test_output
    @formatter = Slk::Formatters::DeactivationFormatter.new(output: @output, width: 60)
  end

  def io_string = @output.instance_variable_get(:@io).string

  def record(real_name:, month:, title: nil)
    @seq = @seq.to_i + 1
    Slk::Models::Deactivation.from_api(
      'id' => format('U%03d', @seq), 'name' => real_name.downcase,
      'updated' => Time.new(month[0, 4].to_i, month[5, 2].to_i, 15, 12, 0, 0).to_i,
      'profile' => { 'real_name' => real_name, 'title' => title }
    )
  end

  # A gap in a histogram should read as "nobody left that month", not as a
  # month that never happened — so quiet months are filled in with zero.
  def test_monthly_counts_fills_empty_months
    records = [record(real_name: 'Ann', month: '2026-01'), record(real_name: 'Bob', month: '2026-04')]

    assert_equal({ '2026-01' => 1, '2026-02' => 0, '2026-03' => 0, '2026-04' => 1 },
                 @formatter.monthly_counts(records))
  end

  def test_monthly_counts_spans_a_year_boundary
    records = [record(real_name: 'Ann', month: '2025-11'), record(real_name: 'Bob', month: '2026-02')]

    assert_equal %w[2025-11 2025-12 2026-01 2026-02], @formatter.monthly_counts(records).keys
  end

  def test_monthly_counts_ignores_records_without_a_timestamp
    undated = Slk::Models::Deactivation.from_api({ 'id' => 'U1', 'name' => 'ghost', 'updated' => 0 })

    assert_empty @formatter.monthly_counts([undated])
  end

  def test_chart_is_silent_for_an_empty_list
    @formatter.chart([])

    assert_empty io_string
  end

  # The caller's window, not the records, decides the span: a quiet first or
  # last month is part of the answer.
  def test_monthly_counts_honours_explicit_bounds
    records = [record(real_name: 'Ann', month: '2026-03')]
    counts = @formatter.monthly_counts(records, from: '2026-01', to: '2026-05')

    assert_equal({ '2026-01' => 0, '2026-02' => 0, '2026-03' => 1, '2026-04' => 0, '2026-05' => 0 }, counts)
  end

  def test_explicit_bounds_never_hide_a_record_outside_them
    records = [record(real_name: 'Ann', month: '2025-11'), record(real_name: 'Bob', month: '2026-02')]
    counts = @formatter.monthly_counts(records, from: '2026-01', to: '2026-01')

    assert_equal %w[2025-11 2025-12 2026-01 2026-02], counts.keys
  end

  def test_monthly_counts_is_empty_when_bounds_are_inverted_and_there_are_no_records
    assert_empty @formatter.monthly_counts([], from: '2026-05', to: '2026-01')
  end

  # Rounding a zero up to one block would draw departures that did not happen.
  def test_months_with_no_departures_draw_no_bar
    @formatter.chart([record(real_name: 'Ann', month: '2026-01'), record(real_name: 'Bob', month: '2026-03')])
    quiet = io_string.lines.find { |line| line.start_with?('2026-02') }

    assert_equal '2026-02  0', quiet.chomp
  end

  def test_list_truncates_to_the_configured_width
    long = record(real_name: 'Bartholomew Cuthbert Fitzwilliam Montgomery', month: '2026-01',
                  title: 'Principal Distinguished Staff Engineer of Long Titles')
    @formatter.list([long])

    assert_includes io_string, '…'
    assert(io_string.lines.all? { |line| line.chomp.length <= 60 })
  end

  def test_list_shows_unknown_for_missing_dates
    undated = Slk::Models::Deactivation.from_api({ 'id' => 'U1', 'name' => 'ghost', 'updated' => nil })
    @formatter.list([undated])

    assert_includes io_string, 'unknown'
    assert_includes io_string, 'ghost'
  end

  # --- tenure column ------------------------------------------------------

  def tenure(started, ended_month)
    Slk::Models::Tenure.build(started, Time.new(ended_month[0, 4].to_i, ended_month[5, 2].to_i, 15))
  end

  def test_list_shows_a_tenure_column_when_one_is_known
    record = record(real_name: 'Ann', month: '2026-01', title: 'Engineer')
    @formatter.list([record], tenures: { record.user_id => tenure('2020-01-10', '2026-01') })

    assert_match(/Ann\s+6y\s+Engineer/, io_string)
  end

  # A start date nobody filled in leaves the cell blank rather than guessing.
  def test_rows_without_a_tenure_keep_the_column_blank
    known = record(real_name: 'Ann', month: '2026-01', title: 'Engineer')
    unknown = record(real_name: 'Bob', month: '2026-01', title: 'Designer')
    @formatter.list([known, unknown], tenures: { known.user_id => tenure('2020-01-10', '2026-01') })
    bob = io_string.lines.find { |l| l.include?('Bob') }

    assert_match(/Bob\s+Designer/, bob)
  end

  def test_the_column_disappears_when_no_tenure_is_known
    record = record(real_name: 'Ann', month: '2026-01', title: 'Engineer')
    @formatter.list([record], tenures: {})

    assert_match(/Ann\s+Engineer/, io_string)
    refute_match(/\d+(y|mo)/, io_string.sub(/\A\S+/, ''))
  end

  def test_tenures_are_right_aligned_to_the_widest
    short = record(real_name: 'Ann', month: '2026-01')
    long = record(real_name: 'Bob', month: '2026-01')
    @formatter.list([short, long], tenures: { short.user_id => tenure('2025-11-01', '2026-01'),
                                              long.user_id => tenure('2014-01-01', '2026-01') })
    cells = io_string.lines.map { |l| l[/\s(\S+(?:\s\S+)?)\s*$/, 1] }

    assert_equal %w[2mo 12y], cells
  end

  # Tenure objects exist but none of them knows anything: still no column.
  def test_all_unknown_tenures_drop_the_column_too
    ann = record(real_name: 'Ann', month: '2026-01', title: 'Engineer')
    @formatter.list([ann], tenures: { ann.user_id => Slk::Models::Tenure.build('2026-01-15', nil) })

    refute_match(/\d+(y|mo)/, io_string.sub(/\A\S+/, ''))
  end

  def test_the_tenure_column_does_not_push_rows_past_the_width
    long = record(real_name: 'Bartholomew Cuthbert Fitzwilliam', month: '2026-01',
                  title: 'Principal Distinguished Staff Engineer of Long Titles')
    @formatter.list([long], tenures: { long.user_id => tenure('2014-01-01', '2026-01') })

    assert(io_string.lines.all? { |line| line.chomp.length <= 60 })
  end
end
