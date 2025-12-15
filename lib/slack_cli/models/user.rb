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

      def initialize(id:, name: nil, real_name: nil, display_name: nil, is_bot: false)
        super(
          id: id.to_s.freeze,
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
