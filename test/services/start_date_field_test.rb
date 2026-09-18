# frozen_string_literal: true

require 'test_helper'

class StartDateFieldTest < Minitest::Test
  def cache_store
    @cache_store ||= Slk::Services::CacheStore.new(paths: Slk::TestHelpers::TempPaths.new)
  end

  # Records the schema calls so tests can prove the field is looked up once.
  class FakeTeamApi
    attr_reader :calls

    def initialize(fields)
      @fields = fields
      @calls = 0
    end

    def profile_schema
      @calls += 1
      { 'ok' => true, 'profile' => { 'fields' => @fields } }
    end
  end

  def field(api, cache: nil, on_debug: nil)
    Slk::Services::StartDateField.new(
      team_api: api, workspace_name: 'test', cache_store: cache, on_debug: on_debug
    )
  end

  def test_finds_the_start_date_field_by_label
    api = FakeTeamApi.new([{ 'id' => 'Xf01', 'label' => 'Department', 'type' => 'text' },
                           { 'id' => 'Xf02', 'label' => 'Start Date', 'type' => 'date' }])

    assert_equal 'Xf02', field(api).id
  end

  def test_label_match_ignores_case_and_padding
    api = FakeTeamApi.new([{ 'id' => 'Xf02', 'label' => '  start date ', 'type' => 'date' }])

    assert_equal 'Xf02', field(api).id
  end

  # "started summer 2019" in a text box is not a date, so a date-typed field
  # with the same label wins.
  def test_a_date_typed_field_beats_a_text_one
    api = FakeTeamApi.new([{ 'id' => 'Xf01', 'label' => 'Start Date', 'type' => 'text' },
                           { 'id' => 'Xf02', 'label' => 'Start Date', 'type' => 'date' }])

    assert_equal 'Xf02', field(api).id
  end

  def test_a_text_field_is_used_when_there_is_no_date_one
    api = FakeTeamApi.new([{ 'id' => 'Xf01', 'label' => 'Start Date', 'type' => 'text' }])

    assert_equal 'Xf01', field(api).id
  end

  def test_nil_when_the_workspace_has_no_such_field
    api = FakeTeamApi.new([{ 'id' => 'Xf01', 'label' => 'Favourite Snack', 'type' => 'text' }])

    assert_nil field(api).id
  end

  def test_unrelated_labels_containing_the_words_do_not_match
    api = FakeTeamApi.new([{ 'id' => 'Xf01', 'label' => 'Contract Start Date', 'type' => 'date' }])

    assert_nil field(api).id
  end

  def test_the_schema_is_fetched_once_per_instance
    api = FakeTeamApi.new([{ 'id' => 'Xf02', 'label' => 'Start Date', 'type' => 'date' }])
    subject = field(api)
    3.times { subject.id }

    assert_equal 1, api.calls
  end

  def test_the_field_id_is_cached_across_instances
    fields = [{ 'id' => 'Xf02', 'label' => 'Start Date', 'type' => 'date' }]
    first = FakeTeamApi.new(fields)
    field(first, cache: cache_store).id
    second = FakeTeamApi.new(fields)

    assert_equal 'Xf02', field(second, cache: cache_store).id
    assert_equal 0, second.calls
  end

  # A workspace with no field should not re-ask the schema on every run.
  def test_a_missing_field_is_cached_too
    first = FakeTeamApi.new([])
    field(first, cache: cache_store).id
    second = FakeTeamApi.new([])

    assert_nil field(second, cache: cache_store).id
    assert_equal 0, second.calls
  end

  def test_missing_schema_payload_is_tolerated
    api = Object.new
    def api.profile_schema = { 'ok' => true }

    assert_nil field(api).id
  end

  def test_debug_reports_what_was_found
    messages = []
    api = FakeTeamApi.new([{ 'id' => 'Xf02', 'label' => 'Start Date', 'type' => 'date' }])
    field(api, on_debug: ->(m) { messages << m }).id

    assert_equal ['start date field: Xf02'], messages
  end

  def test_debug_reports_when_nothing_was_found
    messages = []
    field(FakeTeamApi.new([]), on_debug: ->(m) { messages << m }).id

    assert_match(/not found/, messages.first)
  end

  def test_missing_message_points_at_the_debug_command
    assert_match(/slk debug schema/, field(FakeTeamApi.new([])).missing_message)
  end

  # --- malformed schemas ---------------------------------------------------

  # A clear "this workspace cannot do tenure" beats an unexpected error.
  def test_a_null_entry_in_the_field_list_is_skipped
    assert_nil field(FakeTeamApi.new([nil])).id
  end

  def test_fields_that_are_not_hashes_are_ignored
    assert_nil field(FakeTeamApi.new([nil, 'Start Date', 42])).id
  end

  def test_a_good_field_still_wins_among_junk
    assert_equal 'Xf1', field(FakeTeamApi.new([nil, 'noise', { 'id' => 'Xf1', 'label' => 'Start Date' }])).id
  end

  def test_a_fields_value_that_is_not_a_list_is_no_field_at_all
    assert_nil field(FakeTeamApi.new({ 'Xf1' => { 'label' => 'Start Date' } })).id
  end

  def test_a_missing_fields_key_is_no_field_at_all
    assert_nil field(FakeTeamApi.new(nil)).id
  end

  def test_a_field_without_an_id_is_not_usable
    assert_nil field(FakeTeamApi.new([{ 'label' => 'Start Date', 'type' => 'date' }])).id
  end

  def test_a_blank_id_is_not_usable
    assert_nil field(FakeTeamApi.new([{ 'id' => '', 'label' => 'Start Date' }])).id
  end
end
