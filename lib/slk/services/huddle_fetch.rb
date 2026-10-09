# frozen_string_literal: true

module Slk
  module Services
    # Loads active huddles for one or more workspaces.
    #
    # A roster scan is a large download. Workspaces do not share a rate-limit
    # bucket, and one HTTP connection can only read one of them at a time, so
    # more than one workspace is fetched concurrently, each on its own client.
    class HuddleFetch
      def initialize(runner:, output:)
        @runner = runner
        @output = output
        @counts = {}
        @mutex = Mutex.new
      end

      def call(workspaces)
        @parallel = workspaces.size > 1 && @runner.api_client.respond_to?(:isolated)
        fetched = WorkspaceFanout.call(workspaces, parallel: @parallel) do |workspace|
          [workspace, fetch(workspace)]
        end
        fetched.map { |workspace, huddles| report(workspace, huddles) }
      ensure
        @output.clear_progress
      end

      private

      def fetch(workspace)
        client = scan_client
        users = Api::Users.new(client, workspace, on_debug: debug_logger)
        HuddleScanner.group(collect(workspace, users))
      ensure
        close_client(client)
      end

      def collect(workspace, users)
        kept = []
        users.list_each do |page, total|
          kept.concat(HuddleScanner.keep(page))
          note(workspace.name, total)
        end
        kept
      end

      def report(workspace, huddles)
        labeled = huddles.map { |huddle| huddle.with(channel: labeler.label(workspace, huddle.channel_id)) }
        Models::WorkspaceHuddles.new(workspace: workspace.name, huddles: labeled)
      end

      def scan_client
        return @runner.api_client.isolated if @parallel

        @runner.api_client
      end

      # The shared client belongs to the rest of the command. An isolated one
      # exists only for this scan and should not keep its socket open.
      def close_client(client)
        return if client.nil? || client.equal?(@runner.api_client)

        client.close if client.respond_to?(:close)
      end

      def note(name, total)
        @mutex.synchronize do
          @counts[name] = total
          @output.progress(progress_line)
        end
      end

      def progress_line
        return "#{@counts.keys.first}: #{@counts.values.first} members" if @counts.one?

        @counts.map { |name, total| "#{name}: #{total}" }.join(' · ')
      end

      def labeler
        @labeler ||= HuddleChannelLabel.new(
          runner: @runner, cache_store: @runner.cache_store, on_debug: debug_logger
        )
      end

      def debug_logger
        @debug_logger ||= ->(message) { @output.debug(message) }
      end
    end
  end
end
