# frozen_string_literal: true

module Slk
  module Models
    Reaction = Data.define(:name, :count, :users, :timestamps) do
      def self.from_api(data)
        new(
          name: data['name'],
          count: data['count'] || 0,
          users: data['users'] || [],
          timestamps: nil # Will be populated by ReactionEnricher
        )
      end

      def initialize(name:, count: 0, users: [], timestamps: nil)
        count_val = count.to_i
        count_val = 0 if count_val.negative? # Normalize invalid negative counts

        super(
          name: name.to_s.freeze,
          count: count_val,
          users: users.freeze,
          timestamps: timestamps&.freeze
        )
      end

      # Create a new Reaction with timestamps added
      def with_timestamps(timestamp_map)
        Reaction.new(
          name: name,
          count: count,
          users: users,
          timestamps: timestamp_map
        )
      end

      def timestamps?
        !timestamps.nil? && !timestamps.empty?
      end

      def timestamp_for(user_id)
        timestamps&.dig(user_id)
      end

      def emoji_code
        ":#{name}:"
      end

      def to_s
        "#{count} #{emoji_code}"
      end
    end
  end
end
