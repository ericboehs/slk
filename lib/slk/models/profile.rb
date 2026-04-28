# frozen_string_literal: true

module Slk
  module Models
    # Composite model representing a Slack user profile, merged from
    # users.profile.get + users.info + team.profile.get schema.
    #
    # custom_fields is an Array<ProfileField>. resolved_users is a mutable
    # Hash<user_id, Profile> populated by ProfileResolver one level deep
    # for type:user fields (e.g. Supervisor).
    Profile = Data.define(
      :user_id, :real_name, :display_name, :first_name, :last_name,
      :title, :email, :phone, :pronouns, :image_url,
      :status_text, :status_emoji, :status_expiration,
      :tz, :tz_label, :tz_offset, :start_date,
      :is_admin, :is_owner, :is_bot, :is_external, :deleted,
      :team_id, :home_team_name,
      :presence, :sections, :custom_fields, :resolved_users
    ) do
      def presence_label
        case presence
        when 'active' then 'Active'
        when 'away' then 'Away'
        end
      end

      def best_name
        return display_name unless display_name.to_s.empty?
        return real_name unless real_name.to_s.empty?

        user_id
      end

      def external?
        is_external
      end

      # Custom fields with values, ordered by ordering then label.
      # Hidden fields are filtered unless explicitly requested.
      def visible_fields
        custom_fields
          .reject { |f| f.empty? || f.hidden }
          .sort_by { |f| [f.ordering.to_i, f.label.to_s] }
      end

      def people_fields
        visible_fields.select { |f| f.type == 'user' }
      end

      def fields_in_section(section_id)
        visible_fields.select { |f| f.section_id == section_id }
      end

      def section(section_id)
        sections.find { |s| s['id'] == section_id }
      end

      # User IDs from the first non-inverse Supervisor-like field.
      # Prefers a field literally labeled "Supervisor".
      def supervisor_ids
        preferred = people_fields.find { |f| f.label.to_s.casecmp('Supervisor').zero? && !f.inverse }
        preferred ||= people_fields.find { |f| !f.inverse }
        preferred ? preferred.user_ids : []
      end

      def reports_field
        custom_fields.find { |f| f.type == 'user' && f.inverse }
      end
    end
  end
end
