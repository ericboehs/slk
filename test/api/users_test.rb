# frozen_string_literal: true

require 'test_helper'

class UsersApiTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @workspace = mock_workspace('test')
    @api = Slk::Api::Users.new(@mock_client, @workspace)
  end

  def test_get_profile_calls_api
    @mock_client.stub('users.profile.get', {
                        'ok' => true,
                        'profile' => {
                          'status_text' => 'Working',
                          'status_emoji' => ':computer:',
                          'display_name' => 'John'
                        }
                      })

    profile = @api.get_profile
    assert_equal 'Working', profile['status_text']
    assert_equal ':computer:', profile['status_emoji']

    call = @mock_client.calls.last
    assert_equal 'users.profile.get', call[:method]
    assert_equal 'test', call[:workspace]
  end

  def test_get_status_returns_status_model
    @mock_client.stub('users.profile.get', {
                        'ok' => true,
                        'profile' => {
                          'status_text' => 'Lunch',
                          'status_emoji' => ':fork_and_knife:',
                          'status_expiration' => Time.now.to_i + 3600
                        }
                      })

    status = @api.get_status
    assert_kind_of Slk::Models::Status, status
    assert_equal 'Lunch', status.text
    assert_equal ':fork_and_knife:', status.emoji
    assert status.expires?
  end

  def test_set_status_sends_profile
    @mock_client.stub('users.profile.set', { 'ok' => true })

    duration = Slk::Models::Duration.new(seconds: 3600)
    @api.set_status(text: 'Meeting', emoji: ':calendar:', duration: duration)

    call = @mock_client.calls.last
    assert_equal 'users.profile.set', call[:method]
    assert_equal 'Meeting', call[:params][:profile][:status_text]
    assert_equal ':calendar:', call[:params][:profile][:status_emoji]
    assert call[:params][:profile][:status_expiration].positive?
  end

  def test_clear_status
    @mock_client.stub('users.profile.set', { 'ok' => true })

    @api.clear_status

    call = @mock_client.calls.last
    assert_equal '', call[:params][:profile][:status_text]
    assert_equal '', call[:params][:profile][:status_emoji]
  end

  def test_get_presence
    @mock_client.stub('users.getPresence', {
                        'ok' => true,
                        'presence' => 'active',
                        'manual_away' => false,
                        'online' => true
                      })

    result = @api.get_presence
    assert_equal 'active', result[:presence]
    assert_equal false, result[:manual_away]
    assert_equal true, result[:online]
  end

  def test_set_presence
    @mock_client.stub('users.setPresence', { 'ok' => true })

    @api.set_presence('away')

    call = @mock_client.calls.last
    assert_equal 'users.setPresence', call[:method]
    assert_equal 'away', call[:params][:presence]
  end

  def test_list_users
    @mock_client.stub('users.list', {
                        'ok' => true,
                        'members' => [
                          { 'id' => 'U123', 'name' => 'alice' },
                          { 'id' => 'U456', 'name' => 'bob' }
                        ]
                      })

    result = @api.list
    assert_equal 2, result['members'].size
    assert_equal 'alice', result['members'][0]['name']
  end

  def test_muted_channels_from_legacy_format
    @mock_client.stub('users.prefs.get', {
                        'ok' => true,
                        'prefs' => {
                          'muted_channels' => 'C123,C456,C789'
                        }
                      })

    muted = @api.muted_channels
    assert_equal %w[C123 C456 C789], muted
  end

  def test_muted_channels_from_new_format
    notifications = {
      'channels' => {
        'C123' => { 'muted' => true },
        'C456' => { 'muted' => false },
        'C789' => { 'muted' => true }
      }
    }
    @mock_client.stub('users.prefs.get', {
                        'ok' => true,
                        'prefs' => {
                          'muted_channels' => nil,
                          'all_notifications_prefs' => JSON.generate(notifications)
                        }
                      })

    muted = @api.muted_channels
    assert_includes muted, 'C123'
    assert_includes muted, 'C789'
    refute_includes muted, 'C456'
  end

  def test_profile_for_passes_user_id_and_include_labels
    @mock_client.stub('users.profile.get', { 'ok' => true, 'profile' => { 'real_name' => 'Alice' } })

    response = @api.profile_for('U123ABC')
    assert_equal 'Alice', response['profile']['real_name']

    call = @mock_client.calls.last
    assert_equal 'users.profile.get', call[:method]
    assert_equal 'U123ABC', call[:params][:user]
    assert_equal true, call[:params][:include_labels]
  end

  def test_profile_for_omits_include_labels_when_disabled
    @mock_client.stub('users.profile.get', { 'ok' => true, 'profile' => {} })
    @api.profile_for('U123ABC', include_labels: false)

    call = @mock_client.calls.last
    refute call[:params].key?(:include_labels)
  end

  def test_muted_channels_handles_invalid_json_silently
    @mock_client.stub('users.prefs.get', {
                        'ok' => true,
                        'prefs' => { 'all_notifications_prefs' => '{not json' }
                      })
    debug = []
    api = Slk::Api::Users.new(@mock_client, @workspace, on_debug: ->(m) { debug << m })
    assert_equal [], api.muted_channels
    assert_match(/Failed to parse/, debug.first)
  end

  def test_muted_channels_invalid_json_without_on_debug
    @mock_client.stub('users.prefs.get', {
                        'ok' => true,
                        'prefs' => { 'all_notifications_prefs' => '{not json' }
                      })
    api = Slk::Api::Users.new(@mock_client, @workspace) # no on_debug
    assert_equal [], api.muted_channels
  end

  def test_muted_channels_legacy_empty_string_falls_through
    @mock_client.stub('users.prefs.get', { 'ok' => true, 'prefs' => { 'muted_channels' => '' } })
    assert_equal [], @api.muted_channels
  end

  def test_muted_channels_with_no_channels_in_new_format
    @mock_client.stub('users.prefs.get', {
                        'ok' => true,
                        'prefs' => { 'all_notifications_prefs' => JSON.generate({}) }
                      })
    assert_equal [], @api.muted_channels
  end

  def test_get_presence_for_passes_user_id
    @mock_client.stub('users.getPresence', { 'ok' => true, 'presence' => 'active' })
    @api.get_presence_for('U999')
    assert_equal 'U999', @mock_client.calls.last[:params][:user]
  end

  def test_info_passes_user_id
    @mock_client.stub('users.info', { 'ok' => true, 'user' => { 'id' => 'U1' } })
    @api.info('U1')
    assert_equal 'U1', @mock_client.calls.last[:params][:user]
  end

  def test_list_with_cursor_includes_pagination_param
    @mock_client.stub('users.list', { 'ok' => true, 'members' => [] })
    @api.list(cursor: 'next_cursor')
    assert_equal 'next_cursor', @mock_client.calls.last[:params][:cursor]
  end

  def test_conversations_with_cursor
    @mock_client.stub('users.conversations', { 'ok' => true, 'channels' => [] })
    @api.conversations(cursor: 'next')
    assert_equal 'next', @mock_client.calls.last[:params][:cursor]
  end

  def test_conversations_without_cursor
    @mock_client.stub('users.conversations', { 'ok' => true, 'channels' => [] })
    @api.conversations
    refute @mock_client.calls.last[:params].key?(:cursor)
  end

  def test_muted_channels_returns_empty_when_no_data
    @mock_client.stub('users.prefs.get', {
                        'ok' => true,
                        'prefs' => {}
                      })

    muted = @api.muted_channels
    assert_equal [], muted
  end

  # Scripted pages for the cursor contract: one response per call, in order.
  class ScriptedClient < Slk::TestHelpers::MockApiClient
    def initialize(responses)
      super()
      @responses_in_order = responses
    end

    def post(workspace, method, params = {})
      @calls << { workspace: workspace.name, method: method, params: params }
      @responses_in_order.shift || { 'ok' => true, 'members' => [] }
    end
  end

  def page(members, cursor: '')
    { 'ok' => true, 'members' => members, 'response_metadata' => { 'next_cursor' => cursor } }
  end

  def scripted(responses)
    client = ScriptedClient.new(responses)
    [client, Slk::Api::Users.new(client, @workspace)]
  end

  def test_list_all_follows_the_cursor_across_pages
    _client, api = scripted([page([{ 'id' => 'U1' }], cursor: 'c1'), page([{ 'id' => 'U2' }])])

    assert_equal(%w[U1 U2], api.list_all.map { |m| m['id'] })
  end

  def test_list_all_passes_the_cursor_and_limit_through
    client, api = scripted([page([{ 'id' => 'U1' }], cursor: 'c1'), page([])])
    api.list_all(limit: 7)

    assert_equal([{ limit: 7 }, { limit: 7, cursor: 'c1' }], client.calls.map { |c| c[:params] })
  end

  def test_list_all_reports_the_running_total
    _client, api = scripted([page([{ 'id' => 'U1' }, { 'id' => 'U2' }], cursor: 'c1'), page([{ 'id' => 'U3' }])])
    totals = []
    api.list_all { |total| totals << total }

    assert_equal [2, 3], totals
  end

  def test_list_all_stops_when_response_metadata_is_missing
    _client, api = scripted([{ 'ok' => true, 'members' => [{ 'id' => 'U1' }] }])

    assert_equal(%w[U1], api.list_all.map { |m| m['id'] })
  end

  def test_list_all_tolerates_a_page_with_no_members_key
    _client, api = scripted([{ 'ok' => true, 'response_metadata' => { 'next_cursor' => 'c1' } },
                             page([{ 'id' => 'U1' }])])

    assert_equal(%w[U1], api.list_all.map { |m| m['id'] })
  end

  # A cursor that comes back unchanged would page forever against a live API.
  def test_list_all_raises_on_a_repeating_cursor
    _client, api = scripted([page([{ 'id' => 'U1' }], cursor: 'c1'), page([{ 'id' => 'U2' }], cursor: 'c1')])

    error = assert_raises(Slk::ApiError) { api.list_all }
    assert_equal :invalid_cursor, error.code
    assert_match(/repeating cursor/, error.message)
  end
end
