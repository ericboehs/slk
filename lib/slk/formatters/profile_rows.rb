# frozen_string_literal: true

module Slk
  module Formatters
    # Builds [label, value] row pairs from a Models::Profile.
    # Pure data — no output, formatting handled by ProfileFormatter.
    class ProfileRows
      def initialize(field_renderer:, emoji_replacer: nil)
        @fields = field_renderer
        @emoji_replacer = emoji_replacer
      end

      def compact(profile)
        contact(profile) + base(profile) + people(profile) + about(profile, skip_title: true)
      end

      def contact(profile)
        [['Email', profile.email], ['Phone', profile.phone]]
      end

      def base(profile)
        [
          ['Presence', profile.presence_label],
          ['Status', status_text(profile)],
          ['Local', local_time(profile)]
        ]
      end

      def people(profile)
        profile.people_fields.flat_map do |field|
          field.user_ids.map { |uid| [field.label, @fields.render_user_reference(uid, profile)] }
        end
      end

      def about(profile, skip_title: false)
        fields = profile.visible_fields.reject { |f| f.type == 'user' }
        fields = fields.reject { |f| skip_title && duplicate_title?(f, profile) }
        fields.map { |f| [f.label, @fields.render(f, profile)] }
      end

      def external(profile)
        contact(profile) + [['Workspace', profile.home_team_name]]
      end

      private

      def duplicate_title?(field, profile)
        field.label.casecmp('Title').zero? && field.value.to_s == profile.title.to_s
      end

      def status_text(profile)
        return nil if profile.status_text.empty? && profile.status_emoji.empty?

        emoji = render_emoji(profile.status_emoji)
        [emoji, profile.status_text].reject(&:empty?).join(' ')
      end

      def render_emoji(text)
        return text if text.to_s.empty? || @emoji_replacer.nil?

        @emoji_replacer.replace(text)
      end

      def local_time(profile)
        return nil unless profile.tz

        time_at_user = Time.now.utc + profile.tz_offset.to_i
        "#{time_at_user.strftime('%-l:%M %p')} #{profile.tz_label}".strip
      end
    end
  end
end
