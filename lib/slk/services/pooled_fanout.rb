# frozen_string_literal: true

module Slk
  module Services
    # Runs a block per item on a few worker threads, each with its own
    # connection, and returns the results in the original order.
    #
    # Net::HTTP is not safe to share across threads, so every worker gets an
    # isolated client and closes it when the queue is empty. A client that
    # cannot isolate (a test double) runs the items one at a time on itself.
    # A failure waits for the other workers, then raises.
    module PooledFanout
      module_function

      def call(items, workers:, client:, &block)
        return items.map { |item| block.call(item, client) } unless pooled?(items, workers, client)

        queue = Queue.new
        items.each_with_index { |item, index| queue << [item, index] }
        queue.close
        results = Array.new(items.size)
        threads = Array.new([workers, items.size].min) { start(queue, results, client, &block) }
        threads.each(&:join)
        threads.each(&:value)
        results
      end

      def pooled?(items, workers, client)
        workers > 1 && items.size > 1 && client.respond_to?(:isolated)
      end

      def start(queue, results, client, &block)
        worker_client = client.isolated
        Thread.new { drain(queue, results, worker_client, &block) }.tap do |thread|
          thread.report_on_exception = false
        end
      end

      def drain(queue, results, client, &block)
        while (job = queue.pop)
          item, index = job
          results[index] = block.call(item, client)
        end
      ensure
        client.close if client.respond_to?(:close)
      end
    end
  end
end
