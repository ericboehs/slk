# frozen_string_literal: true

require 'test_helper'

class ProfileRowsTest < Minitest::Test
  def setup
    @output = test_output(color: false)
    @field_renderer = Slk::Formatters::ProfileFieldRenderer.new(output: @output)
    @emoji_replacer = Slk::Formatters::EmojiReplacer.new
    @rows = Slk::Formatters::ProfileRows.new(
      field_renderer: @field_renderer, emoji_replacer: @emoji_replacer
    )
  end

  def base_profile(overrides = {})
    base = {
      user_id: 'U1', real_name: 'Alice Anderson', display_name: 'al',
      first_name: 'Alice', last_name: 'Anderson',
      title: 'Engineer', email: 'a@x', phone: '555', pronouns: 'she/her', image_url: nil,
      status_text: '', status_emoji: '', status_expiration: 0,
      tz: nil, tz_label: nil, tz_offset: 0, start_date: nil,
      is_admin: false, is_owner: false, is_bot: false, is_external: false,
      deleted: false, team_id: 'T1', home_team_name: 'Home',
      presence: 'active', sections: [], custom_fields: [], resolved_users: {}
    }.merge(overrides)
    Slk::Models::Profile.new(**base)
  end

  def field(overrides = {})
    base = {
      id: 'X', label: 'L', value: '', alt: '', type: 'text',
      ordering: 0, section_id: 'S1', hidden: false, inverse: false
    }.merge(overrides)
    Slk::Models::ProfileField.new(**base)
  end

  def test_contact
    profile = base_profile
    rows = @rows.contact(profile)
    assert_equal [['Email', 'a@x'], ['Phone', '555']], rows
  end

  def test_base_with_status_and_local_time
    profile = base_profile(
      status_text: 'In a meeting', status_emoji: ':calendar:',
      tz: 'America/Chicago', tz_label: 'CDT', tz_offset: -18_000
    )
    rows = @rows.base(profile)
    labels = rows.map(&:first)
    assert_equal %w[Presence Status Local], labels
    status_value = rows.find { |r| r.first == 'Status' }.last
    assert_includes status_value, 'In a meeting'
    local = rows.find { |r| r.first == 'Local' }.last
    refute_nil local
    assert_includes local, 'CDT'
  end

  def test_base_status_nil_when_empty
    profile = base_profile
    status = @rows.base(profile).find { |r| r.first == 'Status' }.last
    assert_nil status
  end

  def test_base_local_nil_when_no_tz
    profile = base_profile
    local = @rows.base(profile).find { |r| r.first == 'Local' }.last
    assert_nil local
  end

  def test_about_excludes_user_fields_and_skips_duplicate_title
    fields = [
      field(label: 'Title', value: 'Engineer', ordering: 0),
      field(label: 'Bio', value: 'Hello', ordering: 1),
      field(label: 'Boss', value: 'U2', type: 'user', ordering: 2)
    ]
    profile = base_profile(custom_fields: fields)
    rows = @rows.about(profile, skip_title: true)
    labels = rows.map(&:first)
    refute_includes labels, 'Title'
    refute_includes labels, 'Boss'
    assert_includes labels, 'Bio'
  end

  def test_about_keeps_title_when_not_skip_title
    fields = [field(label: 'Title', value: 'Engineer', ordering: 0)]
    profile = base_profile(custom_fields: fields)
    rows = @rows.about(profile, skip_title: false)
    assert_equal ['Title'], rows.map(&:first)
  end

  def test_people_returns_user_rows
    fields = [field(label: 'Mentor', value: 'U2,U3', type: 'user')]
    resolved = {
      'U2' => base_profile(user_id: 'U2', real_name: 'Bob', display_name: 'bob'),
      'U3' => base_profile(user_id: 'U3', real_name: 'Carol', display_name: 'carol')
    }
    profile = base_profile(custom_fields: fields, resolved_users: resolved)
    rows = @rows.people(profile)
    assert_equal 2, rows.size
    assert(rows.all? { |r| r.first == 'Mentor' })
  end

  def test_compact_combines_sections
    fields = [field(label: 'Bio', value: 'Hi', ordering: 1)]
    profile = base_profile(custom_fields: fields)
    rows = @rows.compact(profile)
    labels = rows.map(&:first)
    assert_includes labels, 'Email'
    assert_includes labels, 'Bio'
  end

  def test_external_returns_workspace_row
    profile = base_profile(home_team_name: 'External Team')
    rows = @rows.external(profile)
    workspace_row = rows.find { |r| r.first == 'Workspace' }
    assert_equal 'External Team', workspace_row.last
  end

  def test_status_with_emoji_only
    profile = base_profile(status_text: '', status_emoji: ':smile:')
    status = @rows.base(profile).find { |r| r.first == 'Status' }.last
    refute_nil status
  end

  def test_render_emoji_returns_text_when_no_replacer
    rows = Slk::Formatters::ProfileRows.new(field_renderer: @field_renderer, emoji_replacer: nil)
    profile = base_profile(status_emoji: ':smile:', status_text: '')
    status = rows.base(profile).find { |r| r.first == 'Status' }.last
    assert_includes status, ':smile:'
  end
end
