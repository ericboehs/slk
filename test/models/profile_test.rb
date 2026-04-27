# frozen_string_literal: true

require 'test_helper'

class ProfileTest < Minitest::Test
  def base_args
    {
      user_id: 'U123', real_name: 'Alice', display_name: 'al',
      first_name: 'Alice', last_name: 'Smith',
      title: nil, email: nil, phone: nil, pronouns: nil, image_url: nil,
      status_text: '', status_emoji: '', status_expiration: 0,
      tz: nil, tz_label: nil, tz_offset: 0, start_date: nil,
      is_admin: false, is_owner: false, is_bot: false, is_external: false,
      deleted: false, team_id: nil, home_team_name: nil, presence: nil,
      sections: [], custom_fields: [], resolved_users: {}
    }
  end

  def field(overrides = {})
    Slk::Models::ProfileField.new(
      id: 'Xf01', label: 'Supervisor', value: 'U999', alt: '', type: 'user',
      ordering: 1, section_id: 'Sec1', hidden: false, inverse: false
    ).then { |f| Slk::Models::ProfileField.new(**f.to_h, **overrides) }
  end

  def test_best_name_prefers_display
    profile = Slk::Models::Profile.new(**base_args)
    assert_equal 'al', profile.best_name
  end

  def test_best_name_falls_back_to_real_name
    profile = Slk::Models::Profile.new(**base_args, display_name: '')
    assert_equal 'Alice', profile.best_name
  end

  def test_supervisor_ids_splits_comma_separated
    fields = [field(value: 'U001,U002,U003')]
    profile = Slk::Models::Profile.new(**base_args, custom_fields: fields)
    assert_equal %w[U001 U002 U003], profile.supervisor_ids
  end

  def test_supervisor_ids_prefers_label_supervisor
    fields = [
      field(label: 'Mentor', value: 'U_mentor'),
      field(label: 'Supervisor', value: 'U_super')
    ]
    profile = Slk::Models::Profile.new(**base_args, custom_fields: fields)
    assert_equal ['U_super'], profile.supervisor_ids
  end

  def test_supervisor_ids_skips_inverse_fields
    fields = [field(label: 'Direct Reports', value: 'U_report', inverse: true)]
    profile = Slk::Models::Profile.new(**base_args, custom_fields: fields)
    assert_empty profile.supervisor_ids
  end

  def test_visible_fields_excludes_hidden_and_empty
    fields = [
      field(label: 'Empty', value: ''),
      field(label: 'Hidden', value: 'V', hidden: true),
      field(label: 'Visible', value: 'V')
    ]
    profile = Slk::Models::Profile.new(**base_args, custom_fields: fields)
    assert_equal ['Visible'], profile.visible_fields.map(&:label)
  end

  def test_external_flag
    profile = Slk::Models::Profile.new(**base_args, is_external: true, team_id: 'T999')
    assert profile.external?
  end

  def test_best_name_falls_back_to_user_id
    profile = Slk::Models::Profile.new(**base_args, display_name: '', real_name: '')
    assert_equal 'U123', profile.best_name
  end

  def test_presence_label_active
    profile = Slk::Models::Profile.new(**base_args, presence: 'active')
    assert_equal 'Active', profile.presence_label
  end

  def test_presence_label_away
    profile = Slk::Models::Profile.new(**base_args, presence: 'away')
    assert_equal 'Away', profile.presence_label
  end

  def test_presence_label_nil_for_unknown
    profile = Slk::Models::Profile.new(**base_args, presence: nil)
    assert_nil profile.presence_label
  end

  def test_people_fields_filters_user_type
    fields = [field, field(label: 'Bio', type: 'text', value: 'about me')]
    profile = Slk::Models::Profile.new(**base_args, custom_fields: fields)
    assert_equal ['Supervisor'], profile.people_fields.map(&:label)
  end

  def test_fields_in_section_filters_by_section_id
    fields = [
      field(section_id: 'A', label: 'A1', value: 'v'),
      field(section_id: 'B', label: 'B1', value: 'v')
    ]
    profile = Slk::Models::Profile.new(**base_args, custom_fields: fields)
    assert_equal ['A1'], profile.fields_in_section('A').map(&:label)
  end

  def test_section_finder
    sections = [{ 'id' => 'S1', 'label' => 'First' }, { 'id' => 'S2', 'label' => 'Second' }]
    profile = Slk::Models::Profile.new(**base_args, sections: sections)
    assert_equal 'First', profile.section('S1')['label']
    assert_nil profile.section('SX')
  end

  def test_supervisor_ids_falls_back_to_first_non_inverse
    fields = [field(label: 'Mentor', value: 'U_men')]
    profile = Slk::Models::Profile.new(**base_args, custom_fields: fields)
    assert_equal ['U_men'], profile.supervisor_ids
  end

  def test_supervisor_ids_empty_when_only_inverse
    fields = [field(label: 'Reports', value: 'U_r', inverse: true)]
    profile = Slk::Models::Profile.new(**base_args, custom_fields: fields)
    assert_empty profile.supervisor_ids
  end

  def test_reports_field_returns_inverse_user_field
    fields = [
      field(label: 'Supervisor', value: 'U1'),
      field(label: 'Reports', value: 'U2,U3', inverse: true)
    ]
    profile = Slk::Models::Profile.new(**base_args, custom_fields: fields)
    assert_equal 'Reports', profile.reports_field.label
  end

  def test_visible_fields_sorts_by_ordering
    fields = [
      field(ordering: 3, value: 'c'),
      field(ordering: 1, value: 'a'),
      field(ordering: 2, value: 'b')
    ]
    profile = Slk::Models::Profile.new(**base_args, custom_fields: fields)
    orderings = profile.visible_fields.map(&:ordering)
    assert_equal [1, 2, 3], orderings
  end
end

class ProfileFieldTest < Minitest::Test
  def test_user_ids_only_for_user_type
    text_field = Slk::Models::ProfileField.new(
      id: 'X', label: 'L', value: 'U1,U2', alt: '', type: 'text',
      ordering: 0, section_id: nil, hidden: false, inverse: false
    )
    assert_empty text_field.user_ids
  end

  def test_user_ids_strips_whitespace
    user_field = Slk::Models::ProfileField.new(
      id: 'X', label: 'L', value: ' U1 , U2 ', alt: '', type: 'user',
      ordering: 0, section_id: nil, hidden: false, inverse: false
    )
    assert_equal %w[U1 U2], user_field.user_ids
  end

  def test_link_text_falls_back_to_value
    field = Slk::Models::ProfileField.new(
      id: 'X', label: 'L', value: 'https://example.com', alt: '', type: 'link',
      ordering: 0, section_id: nil, hidden: false, inverse: false
    )
    assert_equal 'https://example.com', field.link_text

    with_alt = Slk::Models::ProfileField.new(**field.to_h, alt: 'Example')
    assert_equal 'Example', with_alt.link_text
  end
end
