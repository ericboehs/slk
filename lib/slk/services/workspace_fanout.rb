# frozen_string_literal: true

module Slk
  module Services
    # Runs one block per item. With parallel, the blocks overlap and the
    # results come back in the original order. A failure waits for the other
    # threads to finish, then raises, so an in-flight request is not abandoned
    # mid-read.
    module WorkspaceFanout
      module_function

      def call(items, parallel: false, &block)
        return items.map(&block) unless parallel && items.size > 1

        threads = items.map { |item| start(item, &block) }
        threads.map(&:value)
      ensure
        Array(threads).each(&:join)
      end

      # The caller raises the thread's exception. Leaving the default on
      # prints a second traceback for a failure the command already reports.
      def start(item, &block)
        Thread.new { block.call(item) }.tap { |thread| thread.report_on_exception = false }
      end
    end
  end
end
