# frozen_string_literal: true

require 'test_helper'

class TenureTest < Minitest::Test
  def tenure(started, ended)
    Slk::Models::Tenure.build(started, ended && Time.new(*ended))
  end

  def test_build_returns_nil_without_a_usable_start_date
    assert_nil Slk::Models::Tenure.build(nil, Time.now)
    assert_nil Slk::Models::Tenure.build('', Time.now)
    assert_nil Slk::Models::Tenure.build('summer 2019', Time.now)
    assert_nil Slk::Models::Tenure.build('2019-13-45', Time.now)
  end

  def test_whole_months_between_the_dates
    assert_equal 12, tenure('2024-01-15', [2025, 1, 15]).months
    assert_equal 31, tenure('2024-02-12', [2026, 9, 14]).months
  end

  # Someone who left on the 3rd having started on the 20th has not completed
  # that month, and rounding it up would inflate every tenure by up to a month.
  def test_a_partial_final_month_does_not_count
    assert_equal 11, tenure('2024-01-20', [2025, 1, 3]).months
    assert_equal 0, tenure('2024-01-20', [2024, 2, 3]).months
  end

  def test_months_is_nil_for_an_account_with_no_end
    assert_nil tenure('2024-01-15', nil).months
  end

  # A start date typed in after the fact can land anywhere. A negative tenure
  # is a data entry error, not a fact about a person.
  def test_months_is_nil_when_the_end_predates_the_start
    assert_nil tenure('2026-05-01', [2024, 1, 1]).months
  end

  def test_to_s_reads_in_years_and_months
    assert_equal '1y', tenure('2024-01-15', [2025, 1, 15]).to_s
    assert_equal '2y 7mo', tenure('2024-02-12', [2026, 9, 14]).to_s
    assert_equal '9mo', tenure('2024-01-15', [2024, 10, 20]).to_s
  end

  def test_to_s_admits_when_it_is_under_a_month
    assert_equal '<1mo', tenure('2026-08-20', [2026, 9, 3]).to_s
  end

  def test_to_s_is_empty_when_there_is_nothing_to_measure
    assert_equal '', tenure('2024-01-15', nil).to_s
  end

  def test_started_is_the_iso_date
    assert_equal '2024-02-12', tenure('2024-02-12', [2026, 9, 14]).started
  end

  def test_surrounding_whitespace_is_tolerated
    assert_equal '2024-02-12', Slk::Models::Tenure.build(' 2024-02-12 ', nil).started
  end
end
