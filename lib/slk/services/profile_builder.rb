# frozen_string_literal: true

module Slk
  module Services
    # Builds Models::Profile from raw users.profile.get + users.info +
    # team.profile.get responses. Pure data assembly — no API calls.
    module ProfileBuilder
      module_function

      # rubocop:disable Metrics/MethodLength
      def build(profile_response:, info_response: nil, schema_response: nil, workspace_team_id: nil)
        info_data = extract_info(info_response)
        profile_data = extract_profile(profile_response, info_data)
        schema = extract_schema(schema_response)
        team_id = info_data['team_id'] || profile_data['team']

        Models::Profile.new(
          **identity(profile_data, info_data),
          **status(profile_data),
          **tz(info_data),
          **flags(info_data, team_id, workspace_team_id),
          team_id: team_id,
          home_team_name: nil,
          presence: nil,
          sections: schema[:sections],
          custom_fields: build_fields(profile_data['fields'] || {}, schema[:fields_by_id]),
          resolved_users: {}
        )
      end
      # rubocop:enable Metrics/MethodLength

      # Slack Connect external users often fail users.profile.get with
      # user_not_found, but users.info still returns the same fields nested at
      # user.profile. Fall back to that so we render a useful card.
      def extract_profile(response, info_data = {})
        primary = response.is_a?(Hash) ? (response['profile'] || {}) : {}
        return primary unless primary.empty?

        info_data['profile'] || {}
      end

      def extract_info(response)
        return {} unless response.is_a?(Hash)

        response['user'] || {}
      end

      def extract_schema(response)
        section = response.is_a?(Hash) ? (response['profile'] || {}) : {}
        fields = section['fields'] || []
        {
          fields_by_id: fields.to_h { |f| [f['id'], f] },
          sections: section['sections'] || []
        }
      end

      def identity(profile_data, info_data)
        names(profile_data, info_data).merge(contact(profile_data))
      end

      def names(profile_data, info_data)
        {
          user_id: info_data['id'] || profile_data['id'] || '',
          real_name: profile_data['real_name'] || info_data['real_name'],
          display_name: profile_data['display_name'],
          first_name: profile_data['first_name'],
          last_name: profile_data['last_name']
        }
      end

      def contact(profile_data)
        {
          title: profile_data['title'],
          email: profile_data['email'],
          phone: profile_data['phone'],
          pronouns: profile_data['pronouns'],
          image_url: profile_data['image_512'] || profile_data['image_192'] || profile_data['image_72'],
          start_date: profile_data['start_date']
        }
      end

      def status(profile_data)
        {
          status_text: profile_data['status_text'] || '',
          status_emoji: profile_data['status_emoji'] || '',
          status_expiration: profile_data['status_expiration'] || 0
        }
      end

      def tz(info_data)
        {
          tz: info_data['tz'],
          tz_label: info_data['tz_label'],
          tz_offset: info_data['tz_offset'] || 0
        }
      end

      def flags(info_data, team_id, workspace_team_id)
        {
          is_admin: info_data['is_admin'] || false,
          is_owner: info_data['is_owner'] || false,
          is_bot: info_data['is_bot'] || false,
          is_external: external?(team_id, workspace_team_id),
          deleted: info_data['deleted'] == true
        }
      end

      def external?(team_id, workspace_team_id)
        !!(workspace_team_id && team_id && team_id != workspace_team_id)
      end

      def build_fields(profile_fields, schema_fields_by_id)
        profile_fields.map do |field_id, field_data|
          build_field(field_id, field_data, schema_fields_by_id[field_id] || {})
        end
      end

      def build_field(field_id, field_data, schema)
        Models::ProfileField.new(
          id: field_id, label: field_data['label'] || schema['label'] || field_id,
          value: field_data['value'].to_s, alt: field_data['alt'].to_s,
          type: schema['type'] || 'text', ordering: schema['ordering'].to_i,
          section_id: schema['section_id'],
          hidden: schema['is_hidden'] == true, inverse: schema['is_inverse'] == true
        )
      end
    end
  end
end
