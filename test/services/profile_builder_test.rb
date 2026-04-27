# frozen_string_literal: true

require 'test_helper'

class ProfileBuilderTest < Minitest::Test
  def setup
    @profile = {
      'ok' => true,
      'profile' => {
        'real_name' => 'Alice', 'display_name' => 'al',
        'title' => 'Engineer', 'email' => 'alice@example.com',
        'phone' => '555', 'image_512' => 'https://img/512',
        'status_text' => 'Working', 'status_emoji' => ':computer:',
        'fields' => {
          'Xf01' => { 'value' => 'U999', 'alt' => '', 'label' => 'Supervisor' },
          'Xf02' => { 'value' => '2024-01-01', 'alt' => '', 'label' => 'Start Date' }
        }
      }
    }
    @info = {
      'ok' => true,
      'user' => {
        'id' => 'U123', 'team_id' => 'T_HOME', 'tz' => 'America/Chicago',
        'tz_label' => 'CDT', 'tz_offset' => -18_000, 'is_admin' => false
      }
    }
    @schema = {
      'ok' => true,
      'profile' => {
        'fields' => [
          { 'id' => 'Xf01', 'label' => 'Supervisor', 'type' => 'user', 'ordering' => 2,
            'section_id' => 'S1', 'is_hidden' => false, 'is_inverse' => false },
          { 'id' => 'Xf02', 'label' => 'Start Date', 'type' => 'date', 'ordering' => 1,
            'section_id' => 'S2', 'is_hidden' => false, 'is_inverse' => false }
        ],
        'sections' => [
          { 'id' => 'S1', 'label' => 'People', 'order' => 1 },
          { 'id' => 'S2', 'label' => 'About', 'order' => 2 }
        ]
      }
    }
  end

  def test_builds_internal_profile
    profile = Slk::Services::ProfileBuilder.build(
      profile_response: @profile, info_response: @info, schema_response: @schema,
      workspace_team_id: 'T_HOME'
    )
    assert_equal 'U123', profile.user_id
    assert_equal 'al', profile.best_name
    assert_equal 'Engineer', profile.title
    refute profile.external?
    assert_equal 2, profile.visible_fields.size
  end

  def test_detects_external_via_team_id_mismatch
    profile = Slk::Services::ProfileBuilder.build(
      profile_response: @profile, info_response: @info, schema_response: @schema,
      workspace_team_id: 'T_OTHER'
    )
    assert profile.external?
  end

  def test_field_types_carry_through_from_schema
    profile = Slk::Services::ProfileBuilder.build(
      profile_response: @profile, info_response: @info, schema_response: @schema,
      workspace_team_id: 'T_HOME'
    )
    types = profile.visible_fields.to_h { |f| [f.label, f.type] }
    assert_equal 'user', types['Supervisor']
    assert_equal 'date', types['Start Date']
  end

  def test_handles_missing_info_response
    profile = Slk::Services::ProfileBuilder.build(
      profile_response: @profile, info_response: nil, schema_response: @schema,
      workspace_team_id: 'T_HOME'
    )
    assert_equal 'al', profile.best_name
  end

  def test_handles_missing_schema_response
    profile = Slk::Services::ProfileBuilder.build(
      profile_response: @profile, info_response: @info, schema_response: nil,
      workspace_team_id: 'T_HOME'
    )
    types = profile.visible_fields.map(&:type).uniq
    assert_equal ['text'], types
  end
end
