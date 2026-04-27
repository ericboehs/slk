# frozen_string_literal: true

require 'test_helper'

class ProfileFormatterTest < Minitest::Test
  def setup
    @io = StringIO.new
    @output = Slk::Formatters::Output.new(io: @io, color: false)
    @formatter = Slk::Formatters::ProfileFormatter.new(output: @output)
  end

  def make_field(overrides = {})
    Slk::Models::ProfileField.new(
      id: 'X1', label: 'L', value: 'V', alt: '', type: 'text',
      ordering: 0, section_id: nil, hidden: false, inverse: false, **overrides
    )
  end

  def make_profile(overrides = {})
    Slk::Models::Profile.new(**default_profile_args, **overrides)
  end

  def default_profile_args
    {
      user_id: 'U1', real_name: 'Alice', display_name: 'al',
      first_name: 'Alice', last_name: 'X', title: 'Engineer',
      email: 'alice@example.com', phone: '555-1212', pronouns: 'she/her',
      image_url: nil, status_text: '', status_emoji: '', status_expiration: 0,
      tz: nil, tz_label: nil, tz_offset: 0, start_date: nil,
      is_admin: false, is_owner: false, is_bot: false, is_external: false,
      deleted: false, team_id: nil, home_team_name: nil, presence: nil,
      sections: [], custom_fields: [], resolved_users: {}
    }
  end

  def test_compact_renders_header_and_contact
    @formatter.compact(make_profile)
    out = @io.string
    assert_includes out, 'al'
    assert_includes out, 'Engineer'
    assert_includes out, '(she/her)'
    assert_includes out, 'Email    alice@example.com'
    assert_includes out, 'Phone    555-1212'
  end

  def test_compact_renders_date_field_with_relative_phrase
    field = make_field(label: 'Start Date', value: '2020-01-15', type: 'date')
    @formatter.compact(make_profile(custom_fields: [field]))
    assert_includes @io.string, 'Jan 15, 2020'
    assert_match(/Start Date Jan 15, 2020 \(\d+y( \d+mo)? ago\)/, @io.string)
  end

  def test_compact_renders_link_field_with_alt
    field = make_field(label: 'GitHub', value: 'https://github.com/ericboehs',
                       alt: 'ericboehs', type: 'link')
    @formatter.compact(make_profile(custom_fields: [field]))
    assert_includes @io.string, 'ericboehs'
    assert_includes @io.string, 'github.com'
  end

  def test_compact_renders_user_field_with_resolved_reference
    super_field = make_field(label: 'Supervisor', value: 'U999', type: 'user')
    referenced = make_profile(user_id: 'U999', real_name: 'Boss', display_name: 'boss',
                              title: 'Director', pronouns: 'they/them', email: nil, phone: nil)
    profile = make_profile(custom_fields: [super_field], resolved_users: { 'U999' => referenced })
    @formatter.compact(profile)
    assert_includes @io.string, 'Supervisor boss'
    assert_includes @io.string, '(they/them)'
    assert_includes @io.string, 'Director'
  end

  def test_full_groups_into_sections
    fields = [
      make_field(label: 'Supervisor', value: 'U2', type: 'user', section_id: 'S_people'),
      make_field(label: 'Program', value: 'EERT', type: 'text', section_id: 'S_about')
    ]
    referenced = make_profile(user_id: 'U2', real_name: 'Boss', display_name: 'boss',
                              title: nil, email: nil, phone: nil, pronouns: nil)
    profile = make_profile(custom_fields: fields, resolved_users: { 'U2' => referenced })

    @formatter.full(profile)
    out = @io.string
    assert_includes out, 'Contact information'
    assert_includes out, 'People'
    assert_includes out, 'About me'
    assert_includes out, 'Program  EERT'
  end

  def test_full_external_user_skips_sections
    profile = make_profile(is_external: true, team_id: 'T_OTHER',
                           home_team_name: 'innoVet Health', phone: nil, pronouns: nil)
    @formatter.full(profile)
    out = @io.string
    assert_includes out, 'external — innoVet Health'
    assert_includes out, 'Workspace innoVet Health'
    refute_includes out, 'About me'
    refute_includes out, 'People'
  end

  def test_compact_truncates_long_labels
    long = make_field(label: 'A very long label here', value: 'V', type: 'text')
    @formatter.compact(make_profile(custom_fields: [long]))
    assert_includes @io.string, 'A very long label h… V'
  end
end
