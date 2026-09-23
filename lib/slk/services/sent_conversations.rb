# frozen_string_literal: true

require 'bigdecimal'

module Slk
  module Services
    # Expands indexed from:me hits into bounded channel windows, full DM
    # histories and full threads. Search is the seed, not the context source.
    # rubocop:disable Metrics/ClassLength
    class SentConversations
      Conversation = Data.define(:workspace, :channel_id, :channel_name, :channel_type, :type, :thread_ts,
                                 :first_sent_ts, :messages, :last_speaker_is_me, :dropped_messages,
                                 :self_user_id, :self_username)
      DEFAULT_BEFORE = 5
      DEFAULT_AFTER_MINUTES = 30
      DEFAULT_MAX = 200

      # A date span plus three independent window/output limits.
      # rubocop:disable Metrics/ParameterLists
      def initialize(runner:, start_date:, end_date:, before: DEFAULT_BEFORE,
                     after_minutes: DEFAULT_AFTER_MINUTES, max: DEFAULT_MAX)
        @runner = runner
        @start_date = start_date
        @end_date = end_date
        @before = before
        @after_seconds = after_minutes * 60
        @max = max
      end
      # rubocop:enable Metrics/ParameterLists

      def collect(entries)
        @self_ids = entries.to_h { |workspace, result| [workspace.name, self_id(workspace, result)] }
        groups = entries.group_by { |workspace, result| [workspace.name, result.channel_id] }
        conversations = groups.flat_map { |_key, group| collect_channel(group) }
        # A thread parent can also appear in a channel window / DM history.
        # Thread owns the message so the same (channel, ts) is never repeated.
        deduplicate(conversations).sort_by { |conversation| conversation.first_sent_ts.to_f }
      end

      private

      # Partitioning a channel needs both the reply roots and unthreaded hits.
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity
      def collect_channel(group)
        workspace, seed = group.first
        hits = group.map(&:last)
        @self_id = @self_ids[workspace.name]
        @api = @runner.conversations_api(workspace.name)
        threaded = hits.select { |hit| hit.thread_ts && hit.thread_ts != hit.ts }.group_by(&:thread_ts)
        ordinary = hits.reject { |hit| threaded.key?(hit.thread_ts) || threaded.key?(hit.ts) }
        threads = threaded.map do |root, results|
          parent_hit = hits.find { |hit| hit.ts == root }
          thread_hits = parent_hit ? [parent_hit, *results] : results
          thread_conversation(workspace, seed, root, thread_hits)
        end
        spans = if seed.dm?
                  ordinary.empty? ? [] : [dm_conversation(workspace, seed, ordinary)]
                else
                  channel_conversations(workspace, seed, ordinary)
                end
        threads + spans
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/MethodLength, Metrics/PerceivedComplexity

      def self_id(workspace, result)
        return result.user_id if result.user_id.to_s.match?(/\A[UW][A-Z0-9]+\z/i)

        cached = @runner.cache_store.get_meta(workspace.name, 'self_user_id')
        return cached if cached

        id = @runner.client_api(workspace.name).auth_test['user_id']
        raise ApiError, "Cannot identify sender in #{workspace.name}" unless id

        @runner.cache_store.set_meta(workspace.name, 'self_user_id', id)
        id
      end

      def thread_conversation(workspace, seed, root, hits)
        raw = thread_messages(seed.channel_id, root)
        build(workspace, seed, 'thread', root, hits, raw)
      end

      def dm_conversation(workspace, seed, hits)
        start_at = @start_date.to_time.to_i
        # Slack's latest is exclusive; +1 includes messages in this second.
        end_at = [(@end_date + 1).to_time.to_i, Time.now.to_i + 1].min
        raw = page_through(:history, channel: seed.channel_id, oldest: start_at.to_s, latest: end_at.to_s)
        build(workspace, seed, seed.channel_type, nil, hits, raw, expand_threads: true)
      end

      def channel_conversations(workspace, seed, hits)
        merge_windows(hits).map { |window| channel_window(workspace, seed, window) }
      end

      def channel_window(workspace, seed, window)
        preceding = preceding_messages(seed.channel_id, window.first.ts)
        following = following_messages(seed.channel_id, window)
        build(workspace, seed, 'channel', nil, window, preceding + following, expand_threads: true)
      end

      def preceding_messages(channel_id, timestamp)
        return [] if @before.zero?

        @api.history(channel: channel_id, latest: timestamp, limit: @before).fetch('messages', [])
      end

      def following_messages(channel_id, window)
        return [] if @after_seconds.zero?

        end_at = (BigDecimal(window.last.ts) + @after_seconds).to_s('F')
        page_through(:history, channel: channel_id, oldest: window.first.ts, latest: end_at, inclusive: true)
      end

      def merge_windows(hits)
        hits.sort_by { |hit| hit.ts.to_f }.each_with_object([]) do |hit, windows|
          if windows.any? && hit.ts.to_f <= windows.last.last.ts.to_f + @after_seconds
            windows.last << hit
          else
            windows << [hit]
          end
        end
      end

      def thread_messages(channel_id, root)
        page_through(:replies, channel: channel_id, timestamp: root)
      end

      # Cursor follow-up is necessary even when the first page is full.
      # rubocop:disable Metrics/MethodLength
      def page_through(endpoint, **params)
        messages = []
        cursor = nil
        loop do
          response = @api.public_send(endpoint, **params, limit: 200, cursor: cursor)
          messages.concat(response.fetch('messages', []))
          break unless response['has_more']

          next_cursor = response.dig('response_metadata', 'next_cursor').to_s
          if next_cursor.empty? || next_cursor == cursor
            raise ApiError, "conversations.#{endpoint} has_more without a new cursor"
          end

          cursor = next_cursor
        end
        messages
      end
      # rubocop:enable Metrics/MethodLength

      # Keep the search hits as a fallback at Slack's exclusive history bounds.
      # rubocop:disable Metrics/ParameterLists
      def build(workspace, seed, type, root, hits, raw, expand_threads: false)
        # Search's own hits ensure an indexed sent message cannot disappear just
        # because history omits thread replies or returns a window boundary.
        raw += hits.map { |hit| search_message(hit) }
        raw = expand_own_threads(raw, seed, hits) if expand_threads
        messages = normalize(raw, seed.channel_id)
        last_is_me = messages.last&.user_id == @self_id
        Conversation.new(workspace: workspace, channel_id: seed.channel_id, channel_name: seed.channel_name,
                         channel_type: seed.channel_type, type: type, thread_ts: root, first_sent_ts: hits.first.ts,
                         messages: messages, last_speaker_is_me: last_is_me, dropped_messages: 0,
                         self_user_id: @self_id, self_username: hits.first.username)
      end
      # rubocop:enable Metrics/ParameterLists

      def search_message(hit)
        { 'ts' => hit.ts, 'user' => @self_id, 'username' => hit.username, 'text' => hit.text,
          'thread_ts' => hit.thread_ts, 'reply_count' => hit.reply_count }
      end

      def expand_own_threads(raw, seed, hits)
        own_roots(raw, seed, hits).each { |root| raw.concat(thread_messages(seed.channel_id, root)) }
        raw
      end

      def own_roots(raw, seed, hits)
        # Five preceding channel messages may include an old post of ours;
        # don't expand its unrelated thread into today's conversation.
        earliest = seed.dm? ? @start_date.to_time.to_i : hits.first.ts.to_f
        raw.filter_map { |message| message['ts'] if own_thread_root?(message, earliest) }.uniq
      end

      def own_thread_root?(message, earliest)
        message['user'] == @self_id && message['reply_count'].to_i.positive? &&
          message['ts'].to_f >= earliest
      end

      def normalize(raw, channel_id)
        raw.select { |message| readable?(message) }
           .uniq { |message| message['ts'] }
           .sort_by { |message| message['ts'].to_f }
           .map { |message| Models::Message.from_api(message, channel_id: channel_id) }
      end

      def readable?(message)
        message['ts'] && (message['user'] || message['bot_id'] || message['username'])
      end

      def deduplicate(conversations)
        seen = {}
        conversations.filter_map { |conversation| unique_conversation(conversation, seen) }
      end

      # Global dedupe happens before --max so a duplicate cannot consume a slot.
      # rubocop:disable Metrics/AbcSize
      def unique_conversation(conversation, seen)
        key = [conversation.workspace.name, conversation.channel_id]
        unique = conversation.messages.reject { |message| seen[[*key, message.ts]] }
        return if unique.empty?

        unique.each { |message| seen[[*key, message.ts]] = true }
        kept = @max.zero? ? unique : unique.last(@max)
        conversation.with(messages: kept, dropped_messages: unique.size - kept.size,
                          last_speaker_is_me: unique.last.user_id == @self_ids[conversation.workspace.name])
      end
      # rubocop:enable Metrics/AbcSize
    end
    # rubocop:enable Metrics/ClassLength
  end
end
