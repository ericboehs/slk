# frozen_string_literal: true

module Slk
  module Models
    # A single custom profile field from users.profile.get + team.profile.get schema.
    #
    # `value` is the raw string from Slack: a date as YYYY-MM-DD for type:date,
    # a comma-separated list of user IDs for type:user, a URL for type:link.
    # `alt` is Slack's optional display label (e.g. link text).
    ProfileField = Data.define(
      :id, :label, :value, :alt, :type, :ordering, :section_id, :hidden, :inverse
    ) do
      def empty?
        value.to_s.empty?
      end

      # type:user values can be multi-value (comma-separated user IDs).
      def user_ids
        return [] unless type == 'user'

        value.to_s.split(',').map(&:strip).reject(&:empty?)
      end

      def link_text
        alt.to_s.empty? ? value.to_s : alt.to_s
      end
    end
  end
end
