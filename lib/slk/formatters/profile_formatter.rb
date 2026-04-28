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
        field_renderer = ProfileFieldRenderer.new(output: output)
        @rows = ProfileRows.new(field_renderer: field_renderer, emoji_replacer: emoji_replacer)
      end

      def compact(profile)
        render_header(profile)
        emit_rows(@rows.compact(profile))
        nil
      end

      def full(profile)
        render_header(profile)
        return emit_rows(@rows.external(profile)) if profile.external?

        render_section('Contact information', @rows.contact(profile))
        render_section('People', @rows.people(profile))
        render_section('About me', @rows.about(profile))
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
        header_tags(profile).each { |tag| @output.puts("  #{tag}") }
        @output.puts
      end

      def header_tags(profile)
        tags = []
        tags << profile.title unless profile.title.to_s.empty?
        tags << external_tag(profile) if profile.external?
        tags << @output.bold('deactivated account') if profile.deleted
        tags
      end

      def pronouns_suffix(profile)
        profile.pronouns.to_s.empty? ? '' : " #{@output.gray("(#{profile.pronouns})")}"
      end

      def external_tag(profile)
        @output.gray("external — #{profile.home_team_name || 'external workspace'}")
      end

      def render_section(title, rows)
        return if rows.reject { |_, v| v.nil? || v.to_s.empty? }.empty?

        @output.puts(@output.bold(title))
        emit_rows(rows)
        @output.puts
      end

      def emit_row(label, value, width)
        padded = label_for(label).ljust(width)
        @output.puts("  #{@output.gray(padded)} #{value}")
      end
    end
  end
end
