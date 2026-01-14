# frozen_string_literal: true

module SlackCli
  module Models
    User = Data.define(:id, :name, :real_name, :display_name, :is_bot) do
      def self.from_api(data)
        profile = data["profile"] || {}

        new(
          id: data["id"],
          name: data["name"],
          real_name: profile["real_name"] || data["real_name"],
          display_name: profile["display_name"] || profile["display_name_normalized"],
          is_bot: data["is_bot"] || false
        )
      end

      # Slack user IDs start with U or W (enterprise grid)
      USER_ID_PATTERN = /\A[UW][A-Z0-9]+\z/

      def initialize(id:, name: nil, real_name: nil, display_name: nil, is_bot: false)
        id_str = id.to_s.strip
        raise ArgumentError, "user id cannot be empty" if id_str.empty?

        # Validate user ID format (starts with U or W followed by alphanumeric)
        unless id_str.match?(USER_ID_PATTERN)
          raise ArgumentError, "invalid user id format: #{id_str} (expected U or W prefix)"
        end

        super(
          id: id_str.freeze,
          name: name&.freeze,
          real_name: real_name&.freeze,
          display_name: display_name&.freeze,
          is_bot: is_bot
        )
      end

      def best_name
        return display_name unless display_name.to_s.empty?
        return real_name unless real_name.to_s.empty?
        return name unless name.to_s.empty?

        id
      end

      def mention
        "@#{best_name}"
      end

      def to_s
        best_name
      end
    end
  end
end
