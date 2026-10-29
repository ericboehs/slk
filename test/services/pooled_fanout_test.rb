# frozen_string_literal: true

require 'test_helper'

class PooledFanoutTest < Minitest::Test
  class FakeClient
    attr_reader :children

    def initialize
      @children = []
      @mutex = Mutex.new
      @closed = false
    end

    def isolated
      FakeClient.new.tap { |child| @mutex.synchronize { @children << child } }
    end

    def close = @closed = true
    def closed? = @closed
  end

  def test_keeps_order_and_closes_each_worker_client
    client = FakeClient.new
    results = Slk::Services::PooledFanout.call((1..10).to_a, workers: 3, client: client) do |item, worker|
      sleep(rand / 100)
      [item * 2, worker]
    end

    assert_equal (1..10).map { |n| n * 2 }, results.map(&:first)
    assert_equal 3, client.children.size
    assert client.children.all?(&:closed?)
    refute_includes results.map(&:last), client
    refute client.closed?
  end

  def test_runs_on_the_client_itself_when_it_cannot_isolate
    client = Object.new
    results = Slk::Services::PooledFanout.call([1, 2], workers: 4, client: client) { |item, worker| [item, worker] }

    assert_equal [[1, client], [2, client]], results
  end

  def test_single_item_does_not_spawn_workers
    client = FakeClient.new
    Slk::Services::PooledFanout.call([1], workers: 4, client: client) { |item, _| item }

    assert_empty client.children
  end

  def test_a_failure_raises_after_every_worker_finishes
    client = FakeClient.new
    error = assert_raises(RuntimeError) do
      Slk::Services::PooledFanout.call([1, 2, 3], workers: 2, client: client) do |item, _|
        raise 'boom' if item == 2

        item
      end
    end

    assert_equal 'boom', error.message
    assert client.children.all?(&:closed?)
  end
end
