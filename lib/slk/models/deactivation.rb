# frozen_string_literal: true

module Slk
  module Models
    # A deactivated Slack account and when it was deactivated.
    #
    # `deactivated_at` comes from the user object's `updated` field, which is
    # the epoch of the last change to that account. For a deactivated account
    # the deactivation is almost always that last change — but an admin who
    # edits a departed user's profile afterwards moves the timestamp forward,
    # so treat it as "last touched", not a payroll record.
    Deactivation = Data.define(
      :user_id, :handle, :real_name, :title, :email, :deactivated_at, :bot
    ) do
      def self.from_api(member)
        profile = member['profile'] || {}

        new(
          user_id: member['id'],
          handle: member['name'],
          real_name: profile['real_name'] || member['real_name'],
          title: profile['title'],
          email: profile['email'],
          deactivated_at: positive_int(member['updated']),
          bot: bot?(member)
        )
      end

      # Rebuild from a JSON round-trip through the meta cache.
      def self.from_cache(hash)
        new(
          user_id: hash['user_id'], handle: hash['handle'], real_name: hash['real_name'],
          title: hash['title'], email: hash['email'],
          deactivated_at: positive_int(hash['deactivated_at']), bot: hash['bot'] ? true : false
        )
      end

      def self.bot?(member)
        member['is_bot'] || member['is_app_user'] || member['id'] == 'USLACKBOT' ? true : false
      end

      def self.positive_int(value)
        int = value.to_i
        int.positive? ? int : nil
      end

      def best_name
        return real_name unless real_name.to_s.empty?
        return handle unless handle.to_s.empty?

        user_id.to_s
      end

      def deactivated_time
        deactivated_at && Time.at(deactivated_at)
      end

      def date
        deactivated_time&.strftime('%Y-%m-%d')
      end

      def month
        deactivated_time&.strftime('%Y-%m')
      end

      # Matches the caller's pattern against every field a human would search
      # by. Case sensitivity is the pattern's to declare, not this method's.
      def matches?(pattern)
        [handle, real_name, title, email, user_id].compact.any? { |field| pattern.match?(field) }
      end

      def to_cache
        to_h.transform_keys(&:to_s)
      end
    end
  end
end
