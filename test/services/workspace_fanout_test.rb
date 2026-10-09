# frozen_string_literal: true

require 'test_helper'

class WorkspaceFanoutTest < Minitest::Test
  def test_sequential_when_not_asked_to_overlap
    order = []
    result = Slk::Services::WorkspaceFanout.call(%w[a b], parallel: false) do |item|
      order << item
      item.upcase
    end

    assert_equal %w[A B], result
    assert_equal %w[a b], order
  end

  def test_parallel_preserves_order
    started = Queue.new
    release = Queue.new
    worker = Thread.new do
      Slk::Services::WorkspaceFanout.call(%w[a b], parallel: true) do |item|
        started << item
        release.pop
        item.upcase
      end
    end

    2.times { assert started.pop(timeout: 1) }
    2.times { release << true }
    assert_equal %w[A B], worker.value
  ensure
    2.times { release << true }
  end

  def test_a_failure_waits_for_the_other_thread
    finished = Queue.new
    error = assert_raises(RuntimeError) do
      Slk::Services::WorkspaceFanout.call(%w[a b], parallel: true) do |item|
        raise 'nope' if item == 'a'

        finished << item
        'ok'
      end
    end

    assert_equal 'nope', error.message
    assert_equal 'b', finished.pop(timeout: 1)
  end
end
