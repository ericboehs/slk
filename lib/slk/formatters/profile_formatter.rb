# frozen_string_literal: true

module Slk
  module Formatters
    # Renders a Models::Profile for `slk who`.
    # Compact mode: teems-style two-column card.
    # Full mode: section-grouped layout matching Slack web UI.
    class ProfileFormatter
      MIN_LABEL_WIDTH = 8
      MAX_LABEL_WIDTH = 20

      def initialize(output:, emoji_replacer: nil)
        @output = output
        @fields = ProfileFieldRenderer.new(output: output)
        @emoji_replacer = emoji_replacer
      end

      def compact(profile)
        render_header(profile)
        emit_rows(compact_rows(profile))
        nil
      end

      def full(profile)
        render_header(profile)
        return render_external(profile) if profile.external?

        render_section('Contact information', contact_rows(profile))
        render_section('People', people_rows(profile))
        render_section('About me', about_rows(profile))
      end

      def emit_rows(rows)
        non_empty = rows.reject { |_, v| v.nil? || v.to_s.empty? }
        width = label_width(non_empty)
        non_empty.each { |label, value| emit_row(label, value, width) }
      end

      def label_width(rows)
        max = rows.map { |label, _| label_for(label).length }.max || 0
        max.clamp(MIN_LABEL_WIDTH, MAX_LABEL_WIDTH)
      end

      def label_for(label)
        text = label.to_s
        text.length > MAX_LABEL_WIDTH ? "#{text[0, MAX_LABEL_WIDTH - 1]}…" : text
      end

      private

      def render_header(profile)
        @output.puts(@output.bold(profile.best_name) + pronouns_suffix(profile))
        @output.puts("  #{profile.title}") unless profile.title.to_s.empty?
        @output.puts("  #{external_tag(profile)}") if profile.external?
        @output.puts
      end

      def pronouns_suffix(profile)
        profile.pronouns.to_s.empty? ? '' : " #{@output.gray("(#{profile.pronouns})")}"
      end

      def external_tag(profile)
        @output.gray("external — #{profile.home_team_name || 'external workspace'}")
      end

      def compact_rows(profile)
        base_rows(profile) + people_rows(profile) + about_rows(profile, skip_title: true)
      end

      def base_rows(profile)
        contact_rows(profile) + [
          ['Presence', profile.presence_label],
          ['Status', status_text(profile)],
          ['Local', local_time(profile)]
        ]
      end

      def contact_rows(profile)
        [['Email', profile.email], ['Phone', profile.phone]]
      end

      def people_rows(profile)
        profile.people_fields.flat_map do |field|
          field.user_ids.map { |uid| [field.label, @fields.render_user_reference(uid, profile)] }
        end
      end

      def about_rows(profile, skip_title: false)
        fields = profile.visible_fields.reject { |f| f.type == 'user' }
        fields = fields.reject { |f| skip_title && duplicate_title?(f, profile) }
        fields.map { |f| [f.label, @fields.render(f, profile)] }
      end

      def duplicate_title?(field, profile)
        field.label.casecmp('Title').zero? && field.value.to_s == profile.title.to_s
      end

      def render_section(title, rows)
        return if rows.reject { |_, v| v.nil? || v.to_s.empty? }.empty?

        @output.puts(@output.bold(title))
        emit_rows(rows)
        @output.puts
      end

      def render_external(profile)
        emit_rows(contact_rows(profile) + [['Workspace', profile.home_team_name]])
      end

      def emit_row(label, value, width)
        padded = label_for(label).ljust(width)
        @output.puts("  #{@output.gray(padded)} #{value}")
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
