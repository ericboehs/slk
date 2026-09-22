# frozen_string_literal: true

require 'bigdecimal'

module Slk
  module Services
    # Stateless diff of watched sent conversations. Search discovers what to
    # watch; exact-ts history/replies determine what actually changed.
    # Orchestration spans workspace watch sets, thread diffs and output windows.
    # rubocop:disable Metrics/ClassLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
    class SentChanges
      Change = Data.define(:conversation, :new_timestamps, :new_count, :new_from_others)
      Conversation = SentConversations::Conversation

      # rubocop:disable Metrics/ParameterLists
      def initialize(runner:, since:, context: 2, max: 200, before: 5, after_minutes: 30)
        @runner = runner
        @since = since
        @since_ts = Support::CheckInTime.timestamp(since)
        @context = context
        @max = max
        @before = before
        @after_minutes = after_minutes
      end
      # rubocop:enable Metrics/ParameterLists

      def collect(entries, workspaces:)
        groups = entries.group_by { |workspace, hit| [workspace.name, hit.channel_id] }
        changes = workspaces.flat_map { |workspace| collect_workspace(workspace, groups) }
        changes.sort_by do |change|
          conversation = change.conversation
          # Trailing identity keys make ties deterministic: sort_by is not
          # stable, and platforms (e.g. Windows CI) order equal keys differently.
          [conversation.last_speaker_is_me ? 1 : 0, -conversation.messages.last.ts.to_f,
           conversation.workspace.name.to_s, conversation.channel_id.to_s, conversation.thread_ts.to_s]
        end
      end

      private

      def collect_workspace(workspace, groups)
        @workspace = workspace
        @api = @runner.conversations_api(workspace.name)
        @self_id = self_id(workspace, groups)
        local = groups.select { |(name, _id), _hits| name == workspace.name }
        changed_threads = local.flat_map { |(_name, _id), entries| thread_changes(entries.map(&:last)) }
        changed_threads.concat(subscribed_changes(changed_threads, local))
        claimed = changed_threads.flat_map { |change| change.conversation.messages.map(&:ts) }.to_h { |ts| [ts, true] }
        other = local.flat_map do |(_name, _id), entries|
          hits = entries.map(&:last)
          hits.first.dm? ? dm_changes(hits, claimed) : channel_changes(hits, claimed)
        end
        changed_threads + other
      end

      def self_id(workspace, groups)
        entries = groups.find { |(name, _id), rows| name == workspace.name && rows.any? }&.last
        hit = entries&.first&.last
        return hit.user_id if hit&.user_id.to_s.match?(/\A[UW][A-Z0-9]+\z/i)

        @runner.cache_store.get_meta(workspace.name, 'self_user_id') ||
          @runner.client_api(workspace.name).auth_test.fetch('user_id')
      end

      def thread_changes(hits)
        metadata = root_metadata(hits)
        hits.map { |hit| [hit.thread_ts || hit.ts, hit] }.uniq(&:first).filter_map do |root, seed|
          parent = metadata[root]
          next if parent && !thread_active?(parent)

          thread_change(seed, root, full_first: parent && parent['latest_reply'])
        end
      end

      # Fetch the watched top-level parents in one paginated history scan per
      # channel. Search often omits reply_count; history has latest_reply.
      def root_metadata(hits)
        roots = hits.select { |hit| top_level?(hit) }.map(&:ts).uniq
        return {} if roots.empty?

        wanted = roots.to_h { |root| [root, true] }
        found = {}
        cursor = nil
        loop do
          response = @api.history(channel: hits.first.channel_id,
                                  oldest: roots.min_by { |root| BigDecimal(root) }, inclusive: true,
                                  limit: 200, cursor: cursor)
          response.fetch('messages', []).each do |message|
            found[message['ts']] = message if wanted[message['ts']]
          end
          break if found.size == wanted.size || !response['has_more']

          cursor = next_cursor!(response, cursor, :history)
        end
        found
      end

      def thread_active?(parent)
        latest = parent['latest_reply']
        return newer?(latest) if latest

        parent['reply_count'].to_i.positive?
      end

      def thread_change(seed, root, require_participation: false, full_first: false)
        full = page_through(:replies, channel: seed.channel_id, timestamp: root) if full_first
        recent = full || page_through(:replies, channel: seed.channel_id, timestamp: root, oldest: @since_ts)
        fresh = after_cutoff(recent)
        # A new top-level post without replies belongs in its channel/DM
        # window, not in a synthetic one-message thread.
        return if fresh.none? { |row| row['ts'] != root }

        full ||= page_through(:replies, channel: seed.channel_id, timestamp: root)
        return if require_participation && full.none? { |row| row['user'] == @self_id }

        context = previous_messages(full, parent_ts: root)
        change(seed, 'thread', root, fresh, context)
      rescue ApiError => e
        raise unless e.message.include?('thread_not_found')
      end

      # Slack's thread view exposes unread followed threads, not a complete
      # subscriptions cursor. Union the first page, and verify participation.
      def subscribed_changes(existing, local)
        response = @runner.threads_api(@workspace.name).get_view(limit: 100)
        known = existing.map { |change| [change.conversation.channel_id, change.conversation.thread_ts] }
        known.concat(local.flat_map do |(_name, channel), entries|
          entries.map { |_workspace, hit| [channel, hit.thread_ts || hit.ts] }
        end)
        response.fetch('threads', []).filter_map do |item|
          root = item['root_msg'] || {}
          channel = root['channel']
          timestamp = root['thread_ts'] || root['ts']
          next unless channel && timestamp && !known.include?([channel, timestamp])

          seed = subscription_seed(channel, timestamp, root)
          next unless seed

          thread_change(seed, timestamp, require_participation: true)
        end
      rescue ApiError
        [] # Optional endpoint: the search-derived watch set still works.
      end

      def subscription_seed(channel, timestamp, root)
        info = @api.info(channel: channel).fetch('channel', {})
        type = if info['is_im']
                 'im'
               elsif info['is_mpim']
                 'mpim'
               else
                 'channel'
               end
        name = type == 'im' ? info['user'] : info['name']
        return unless name

        Models::SearchResult.new(ts: timestamp, user_id: @self_id, username: nil, text: root['text'].to_s,
                                 channel_id: channel, channel_name: name, channel_type: type,
                                 thread_ts: timestamp, reply_count: 0, permalink: nil, files: [])
      end

      def dm_changes(hits, claimed)
        seed = hits.first
        probe = @api.history(channel: seed.channel_id, oldest: @since_ts, limit: 1)
        recent = if probe['has_more']
                   page_through(:history, channel: seed.channel_id, oldest: @since_ts)
                 else
                   probe.fetch('messages', [])
                 end
        fresh = after_cutoff(recent).reject { |row| claimed[row['ts']] }
        return [] if fresh.empty?

        earlier = if @context.zero?
                    []
                  else
                    @api.history(channel: seed.channel_id, latest: @since_ts,
                                 inclusive: true, limit: @context).fetch('messages', [])
                  end
        context = previous_messages(earlier)
        [change(seed, seed.channel_type, nil, fresh, context)]
      end

      def channel_changes(hits, claimed)
        recent = hits.select { |hit| top_level?(hit) && newer?(hit.ts) }
        return [] if recent.empty?

        windows = SentConversations.new(runner: @runner, start_date: @since.to_date, end_date: Date.today,
                                        before: @before, after_minutes: @after_minutes, max: 0).collect(
                                          recent.map { |hit| [@workspace, hit] }
                                        )
        own_timestamps = recent.to_h { |hit| [hit.ts, true] }
        windows.filter_map do |window|
          next unless window.type == 'channel'

          fresh = window.messages.select { |msg| own_timestamps[msg.ts] && !claimed[msg.ts] }
          next if fresh.empty?

          context = previous_messages(window.messages)
          change(hits.first, 'channel', nil, fresh, context)
        end
      end

      def top_level?(hit)
        hit.thread_ts.nil? || hit.thread_ts == hit.ts
      end

      def previous_messages(raw, parent_ts: nil)
        older = raw.select { |row| row_timestamp(row) && !newer?(row_timestamp(row)) }
        older = older.last(@context) unless @context.zero?
        older = [] if @context.zero?
        return older unless parent_ts && @context.positive?

        parent = raw.find { |row| row_timestamp(row) == parent_ts }
        parent && !newer?(parent_ts) ? ([parent] + older.reject { |row| row == parent }.last(@context - 1)) : older
      end

      # Counts and last speaker are calculated before --max hides any output.
      def change(seed, type, root, fresh, context)
        messages = normalize(context + fresh, seed.channel_id)
        new_ts = fresh.map { |row| row_timestamp(row) }.uniq
        new_messages = messages.select { |message| new_ts.include?(message.ts) }
        return if new_messages.empty?

        kept = @max.zero? ? messages : messages.last(@max)
        conversation = Conversation.new(
          workspace: @workspace, channel_id: seed.channel_id, channel_name: seed.channel_name,
          channel_type: seed.channel_type, type: type, thread_ts: root, first_sent_ts: seed.ts,
          messages: kept, last_speaker_is_me: new_messages.last.user_id == @self_id,
          dropped_messages: messages.size - kept.size, self_user_id: @self_id,
          self_username: seed.username, parent_text: parent_preview(messages, root)
        )
        others = new_messages.count { |message| message.user_id != @self_id }
        Change.new(conversation: conversation, new_timestamps: new_ts,
                   new_count: new_messages.size, new_from_others: others)
      end

      def parent_preview(messages, root)
        return unless root

        parent = messages.find { |message| message.ts == root }
        return '[No text]' unless parent

        if parent.text.empty?
          parent.files.any? ? '[file]' : '[No text]'
        else
          parent.text
        end
      end

      def normalize(raw, channel_id)
        raw.map { |row| row.is_a?(Models::Message) ? row : Models::Message.from_api(row, channel_id: channel_id) }
           .uniq(&:ts).sort_by { |message| BigDecimal(message.ts) }
      end

      def after_cutoff(raw)
        raw.select { |row| row['ts'] && newer?(row['ts']) && (row['user'] || row['bot_id'] || row['username']) }
      end

      def row_timestamp(row)
        row.is_a?(Models::Message) ? row.ts : row['ts']
      end

      def newer?(timestamp)
        BigDecimal(timestamp) > BigDecimal(@since_ts)
      end

      def page_through(endpoint, **params)
        messages = []
        cursor = nil
        loop do
          response = @api.public_send(endpoint, **params, limit: 200, cursor: cursor)
          messages.concat(response.fetch('messages', []))
          break unless response['has_more']

          cursor = next_cursor!(response, cursor, endpoint)
        end
        messages
      end

      def next_cursor!(response, previous, endpoint)
        cursor = response.dig('response_metadata', 'next_cursor').to_s
        raise ApiError, "conversations.#{endpoint} has_more without a new cursor" if cursor.empty? || cursor == previous

        cursor
      end
    end
    # rubocop:enable Metrics/ClassLength, Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
  end
end
