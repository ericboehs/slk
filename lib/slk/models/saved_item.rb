# frozen_string_literal: true

module Slk
  module Models
    # State constants for saved items
    SAVED_STATE_SAVED = 'saved'
    SAVED_STATE_IN_PROGRESS = 'in_progress'
    SAVED_STATE_COMPLETED = 'completed'

    # Represents a saved/later item from Slack's saved.list API
    # rubocop:disable Metrics/ParameterLists
    SavedItem = Data.define(
      :item_id,
      :item_type,
      :ts,
      :state,
      :date_created,
      :date_due,
      :date_completed,
      :is_archived
    ) do
      # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
      def self.from_api(data)
        new(
          item_id: data['item_id'] || data['channel_id'] || data['conversation_id'],
          item_type: data['item_type'] || data['type'] || 'message',
          ts: data['ts'] || data['message_ts'],
          state: data['state'] || SAVED_STATE_SAVED,
          date_created: parse_timestamp(data['date_created']),
          date_due: parse_timestamp(data['date_due']),
          date_completed: parse_timestamp(data['date_completed']),
          is_archived: data['is_archived'] || false
        )
      end
      # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity

      def self.parse_timestamp(value)
        return nil if value.nil? || value.to_i.zero?

        value.to_i
      end

      private_class_method :parse_timestamp

      # rubocop:disable Naming/MethodParameterName
      def initialize(
        item_id:,
        item_type: 'message',
        ts: nil,
        state: SAVED_STATE_SAVED,
        date_created: nil,
        date_due: nil,
        date_completed: nil,
        is_archived: false
      )
        super(
          item_id: item_id.to_s.freeze,
          item_type: item_type.to_s.freeze,
          ts: ts&.to_s&.freeze,
          state: state.to_s.freeze,
          date_created: date_created,
          date_due: date_due,
          date_completed: date_completed,
          is_archived: is_archived
        )
      end
      # rubocop:enable Naming/MethodParameterName

      # Channel ID alias for compatibility with message fetching
      alias_method :channel_id, :item_id

      # State predicates
      def completed?
        state == SAVED_STATE_COMPLETED
      end

      def in_progress?
        state == SAVED_STATE_IN_PROGRESS
      end

      def saved?
        state == SAVED_STATE_SAVED
      end

      def archived?
        is_archived
      end

      # Due date helpers
      def due_date?
        !date_due.nil?
      end

      def overdue?
        return false unless due_date?
        return false if completed?

        date_due < Time.now.to_i
      end

      def due_time
        return nil unless due_date?

        Time.at(date_due)
      end

      def created_time
        return nil unless date_created

        Time.at(date_created)
      end

      def completed_time
        return nil unless date_completed

        Time.at(date_completed)
      end

      # Time until/since due date
      def time_until_due
        return nil unless due_date?

        date_due - Time.now.to_i
      end
    end
    # rubocop:enable Metrics/ParameterLists
  end
end
