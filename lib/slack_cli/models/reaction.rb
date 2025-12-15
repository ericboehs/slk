# frozen_string_literal: true

module SlackCli
  module Models
    Reaction = Data.define(:name, :count, :users) do
      def self.from_api(data)
        new(
          name: data["name"],
          count: data["count"] || 0,
          users: data["users"] || []
        )
      end

      def initialize(name:, count: 0, users: [])
        super(
          name: name.to_s.freeze,
          count: count.to_i,
          users: users.freeze
        )
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
