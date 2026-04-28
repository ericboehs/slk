# frozen_string_literal: true

require 'test_helper'

class ProfileFieldRendererTest < Minitest::Test
  def setup
    @output = test_output(color: true)
    @renderer = Slk::Formatters::ProfileFieldRenderer.new(output: @output)
    @plain_output = test_output(color: false)
    @plain_renderer = Slk::Formatters::ProfileFieldRenderer.new(output: @plain_output)
  end

  def field(overrides = {})
    base = {
      id: 'X', label: 'L', value: '', alt: '', type: 'text',
      ordering: 0, section_id: nil, hidden: false, inverse: false
    }.merge(overrides)
    Slk::Models::ProfileField.new(**base)
  end

  def profile_with(resolved_users = {})
    Slk::Models::Profile.new(
      user_id: 'U1', real_name: '', display_name: '', first_name: '', last_name: '',
      title: nil, email: nil, phone: nil, pronouns: nil, image_url: nil,
      status_text: '', status_emoji: '', status_expiration: 0,
      tz: nil, tz_label: nil, tz_offset: 0, start_date: nil,
      is_admin: false, is_owner: false, is_bot: false, is_external: false,
      deleted: false, team_id: nil, home_team_name: nil, presence: nil,
      sections: [], custom_fields: [], resolved_users: resolved_users
    )
  end

  def make_user(id, real_name: 'Alice', title: 'Engineer', pronouns: 'she/her', display_name: 'al')
    Slk::Models::Profile.new(
      user_id: id, real_name: real_name, display_name: display_name, first_name: '',
      last_name: '', title: title, email: nil, phone: nil, pronouns: pronouns,
      image_url: nil, status_text: '', status_emoji: '', status_expiration: 0,
      tz: nil, tz_label: nil, tz_offset: 0, start_date: nil, is_admin: false,
      is_owner: false, is_bot: false, is_external: false, deleted: false,
      team_id: nil, home_team_name: nil, presence: nil, sections: [],
      custom_fields: [], resolved_users: {}
    )
  end

  def test_renders_text_field
    f = field(value: 'Plain text')
    assert_equal 'Plain text', @renderer.render(f, profile_with)
  end

  def test_renders_rich_text_json_with_text_and_emoji
    json = JSON.dump([
                       {
                         'type' => 'rich_text',
                         'elements' => [
                           {
                             'type' => 'rich_text_section',
                             'elements' => [
                               { 'type' => 'text', 'text' => 'Hello ' },
                               { 'type' => 'emoji', 'name' => 'wave' },
                               { 'type' => 'text', 'text' => ' world' }
                             ]
                           }
                         ]
                       }
                     ])
    f = field(value: json)
    out = @renderer.render(f, profile_with)
    assert_includes out, 'Hello'
    assert_includes out, ':wave:'
    assert_includes out, 'world'
  end

  def test_renders_rich_text_with_emoji_no_name
    json = JSON.dump([{ 'type' => 'rich_text',
                        'elements' => [{ 'type' => 'emoji' }] }])
    f = field(value: json)
    assert_equal '', @renderer.render(f, profile_with)
  end

  def test_renders_rich_text_with_non_hash_block
    out = @renderer.flatten_rich_text(['just a string'])
    assert_equal 'just a string', out
  end

  def test_renders_invalid_json_falls_back_to_string
    bad = '[{not json'
    f = field(value: bad)
    assert_equal bad, @renderer.render(f, profile_with)
  end

  def test_renders_link_field_value_only_when_no_alt_and_match
    f = field(type: 'link', value: 'https://example.com', alt: '')
    assert_equal 'https://example.com', @plain_renderer.render(f, profile_with)
  end

  def test_renders_link_field_with_alt_no_color_shows_url_short
    f = field(type: 'link', value: 'https://example.com/path', alt: 'Example')
    out = @plain_renderer.render(f, profile_with)
    assert_includes out, 'Example'
    assert_includes out, '(example.com)'
  end

  def test_renders_link_field_with_color_uses_osc8
    f = field(type: 'link', value: 'https://example.com/path', alt: 'Example')
    out = @renderer.render(f, profile_with)
    assert_includes out, "\e]8;;https://example.com/path\a"
    assert_includes out, "\e]8;;\a"
  end

  def test_renders_link_field_invalid_url_falls_back
    f = field(type: 'link', value: 'not a url with spaces', alt: 'Bad')
    out = @plain_renderer.render(f, profile_with)
    assert_includes out, 'Bad'
  end

  def test_renders_user_field_resolves_to_best_name_with_pronouns_and_title
    user = make_user('U2')
    f = field(type: 'user', value: 'U2')
    out = @renderer.render(f, profile_with('U2' => user))
    assert_includes out, 'al'
    assert_includes out, 'she/her'
    assert_includes out, 'Engineer'
  end

  def test_renders_user_field_unresolved_returns_id
    f = field(type: 'user', value: 'U_unknown')
    out = @renderer.render(f, profile_with({}))
    assert_includes out, 'U_unknown'
  end

  def test_renders_user_field_no_title_no_pronouns
    user = make_user('U2', title: '', pronouns: '')
    f = field(type: 'user', value: 'U2')
    out = @renderer.render(f, profile_with('U2' => user))
    assert_includes out, 'al'
    refute_includes out, '—'
  end

  def test_renders_user_list_multiple
    u1 = make_user('U1', title: 'A')
    u2 = make_user('U2', title: 'B')
    f = field(type: 'user', value: 'U1, U2')
    out = @renderer.render(f, profile_with('U1' => u1, 'U2' => u2))
    assert_includes out, ','
  end

  def test_renders_date_with_relative_phrase_years_months
    f = field(type: 'date', value: '2020-01-15')
    out = @renderer.render(f, profile_with)
    assert_includes out, 'Jan 15, 2020'
    assert_includes out, 'ago'
  end

  def test_renders_date_no_relative_for_future_date
    future = (Date.today + 365).strftime('%Y-%m-%d')
    f = field(type: 'date', value: future)
    out = @renderer.render(f, profile_with)
    refute_includes out, 'ago'
  end

  def test_renders_date_invalid_returns_value
    f = field(type: 'date', value: 'not a date')
    assert_equal 'not a date', @renderer.render(f, profile_with)
  end

  def test_renders_date_only_months_when_less_than_a_year
    six_months_ago = (Date.today << 6).strftime('%Y-%m-%d')
    f = field(type: 'date', value: six_months_ago)
    out = @renderer.render(f, profile_with)
    assert_includes out, 'mo ago'
    refute_match(/\dy /, out)
  end

  def test_renders_date_no_phrase_for_today
    f = field(type: 'date', value: Date.today.strftime('%Y-%m-%d'))
    out = @renderer.render(f, profile_with)
    refute_includes out, 'ago'
  end

  def test_format_text_handles_nil
    assert_equal '', @renderer.format_text(nil)
  end

  def test_relative_phrase_subtract_when_day_smaller
    # A date where target's day is later in the month than today's,
    # exercising the months -= 1 branch in years_months_between.
    today = Date.today
    target_day = [today.day + 5, 28].min
    return skip if target_day == today.day

    target = Date.new(today.year - 1, today.month, target_day)
    f = field(type: 'date', value: target.strftime('%Y-%m-%d'))
    out = @renderer.render(f, profile_with)
    assert_includes out, 'ago'
  end
end
