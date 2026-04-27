# frozen_string_literal: true

module Slk
  module Formatters
    # Renders ProfileField values to display strings (date with relative
    # phrasing, link with alt text, type:user dereferenced via resolved_users).
    class ProfileFieldRenderer
      def initialize(output:)
        @output = output
        @hyperlinks = output.respond_to?(:color?) && output.color?
      end

      def render(field, profile)
        case field.type
        when 'date' then format_date(field.value)
        when 'link' then format_link(field)
        when 'user' then format_user_list(field, profile)
        else format_text(field.value)
        end
      end

      # Slack stores some text fields (notably free-text profile blocks) as
      # rich_text JSON blocks. Detect and flatten to plain text.
      def format_text(value)
        text = value.to_s
        return text unless text.start_with?('[{') && text.include?('rich_text')

        flatten_rich_text(JSON.parse(text))
      rescue JSON::ParserError
        text
      end

      def flatten_rich_text(blocks)
        Array(blocks).flat_map { |block| extract_text_from_block(block) }.join
      end

      def extract_text_from_block(block)
        return [block.to_s] unless block.is_a?(Hash)

        return [block['text'].to_s] if block['type'] == 'text'
        return [block['name'] ? ":#{block['name']}:" : ''] if block['type'] == 'emoji'

        Array(block['elements']).flat_map { |el| extract_text_from_block(el) }
      end

      def render_user_reference(user_id, profile)
        ref = profile.resolved_users[user_id]
        return user_id unless ref

        suffix = ref.title.to_s.empty? ? '' : " — #{ref.title}"
        pronouns = ref.pronouns.to_s.empty? ? '' : " #{@output.gray("(#{ref.pronouns})")}"
        "#{ref.best_name}#{pronouns}#{suffix}"
      end

      private

      def format_user_list(field, profile)
        field.user_ids.map { |uid| render_user_reference(uid, profile) }.join(', ')
      end

      def format_date(value)
        date = parse_date(value) or return value
        relative = relative_phrase(date, Date.today)
        formatted = date.strftime('%b %-d, %Y')
        relative ? "#{formatted} (#{relative})" : formatted
      end

      def parse_date(value)
        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def relative_phrase(then_date, now_date)
        return nil if then_date >= now_date

        years, months = years_months_between(then_date, now_date)
        parts = []
        parts << "#{years}y" if years.positive?
        parts << "#{months}mo" if months.positive?
        parts.empty? ? nil : "#{parts.join(' ')} ago"
      end

      def years_months_between(then_date, now_date)
        months = ((now_date.year - then_date.year) * 12) + (now_date.month - then_date.month)
        months -= 1 if now_date.day < then_date.day
        [months / 12, months % 12]
      end

      def format_link(field)
        url = field.value.to_s
        label = field.alt.to_s.empty? ? url : field.alt
        return url if label == url
        return "#{label} (#{shorten_url(url)})" unless @hyperlinks

        # OSC 8 hyperlink — clickable in iTerm2, Ghostty, Wezterm, Kitty, Vte.
        "\e]8;;#{url}\a#{label}\e]8;;\a"
      end

      def shorten_url(url)
        URI.parse(url).host || url
      rescue URI::InvalidURIError
        url
      end
    end
  end
end
