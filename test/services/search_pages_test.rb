# frozen_string_literal: true

require_relative '../test_helper'

class SearchPagesTest < Minitest::Test
  def test_keeps_page_size_fixed_and_trims_to_limit
    api = FakeSearch.new(total: 250)
    data = Slk::Services::SearchPages.new(api).fetch(query: 'from:me', limit: 150)

    assert_equal 150, data[:results].length
    timestamps = [0, 99, 100, 149].map { |index| data[:results][index].ts }
    assert_equal %w[1.0 100.0 101.0 150.0], timestamps
    assert_equal [[1, 100], [2, 100]], api.calls
    assert data[:truncated]
  end

  def test_unlimited_walks_every_page
    api = FakeSearch.new(total: 215)
    data = Slk::Services::SearchPages.new(api).fetch(query: 'from:me')

    assert_equal 215, data[:results].length
    assert_equal [[1, 100], [2, 100], [3, 100]], api.calls
    refute data[:truncated]
  end

  def test_page_is_starting_offset_for_limit
    api = FakeSearch.new(total: 250)
    data = Slk::Services::SearchPages.new(api).fetch(query: 'from:me', limit: 120, page: 2)

    assert_equal '101.0', data[:results].first.ts
    assert_equal 120, data[:results].length
    assert_equal [[2, 100], [3, 100]], api.calls
    assert data[:truncated]
  end

  def test_missing_pagination_on_full_page_is_an_error_not_silent_truncation
    api = FakeSearch.new(total: 101, pagination: false)
    error = assert_raises(Slk::ApiError) { Slk::Services::SearchPages.new(api).fetch(query: 'from:me') }

    assert_includes error.message, 'omitted pagination'
    assert_raises(Slk::ApiError) do
      Slk::Services::SearchPages.new(FakeSearch.new(total: 101, pagination: false)).fetch(query: 'from:me', limit: 100)
    end
  end

  class FakeSearch
    attr_reader :calls

    def initialize(total:, pagination: true)
      @total = total
      @pagination = pagination
      @calls = []
    end

    def messages(query:, count:, page:, sort_dir:)
      raise 'wrong query' unless query == 'from:me'
      raise 'wrong sort' unless sort_dir == 'desc'

      @calls << [page, count]
      first = ((page - 1) * count) + 1
      matches = (first..[first + count - 1, @total].min).map do |number|
        { 'ts' => "#{number}.0", 'channel' => { 'id' => 'C1', 'name' => 'general' } }
      end
      pagination = if @pagination
                     { 'page_count' => (@total.to_f / count).ceil, 'total_count' => @total }
                   else
                     {}
                   end
      { 'messages' => { 'matches' => matches, 'pagination' => pagination } }
    end
  end
end
