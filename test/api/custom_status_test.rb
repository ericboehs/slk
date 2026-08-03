# frozen_string_literal: true

require 'test_helper'

class CustomStatusApiTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @workspace = mock_workspace('test')
    @api = Slk::Api::CustomStatus.new(@mock_client, @workspace)
  end

  def scheduled_payload(overrides = {})
    {
      'id' => 'CS0BMQDDGWTU',
      'text' => 'Vet Appt',
      'emoji' => ':paw_prints:',
      'is_dnd' => false,
      'is_active' => false,
      'date_scheduled' => 1_785_781_800,
      'date_expire' => 1_785_789_000
    }.merge(overrides)
  end

  def test_list_calls_the_custom_status_endpoint
    @mock_client.stub('users.customStatus.list', { 'ok' => true, 'statuses' => [] })

    @api.list

    assert_equal 'users.customStatus.list', @mock_client.calls.last[:method]
  end

  # Slack omits scheduled_statuses entirely unless this param is sent.
  def test_list_always_sends_statuses_count_per_section
    @mock_client.stub('users.customStatus.list', { 'ok' => true })

    @api.list

    assert_equal '20', @mock_client.calls.last[:params][:statuses_count_per_section]
  end

  def test_list_accepts_a_custom_section_count
    @mock_client.stub('users.customStatus.list', { 'ok' => true })

    @api.list(count_per_section: 5)

    assert_equal '5', @mock_client.calls.last[:params][:statuses_count_per_section]
  end

  def test_scheduled_maps_results_to_models
    @mock_client.stub('users.customStatus.list', {
                        'ok' => true,
                        'statuses' => [scheduled_payload('id' => 'RECENT')],
                        'scheduled_statuses' => [scheduled_payload]
                      })

    scheduled = @api.scheduled

    assert_equal 1, scheduled.size
    assert_instance_of Slk::Models::ScheduledStatus, scheduled.first
    assert_equal 'CS0BMQDDGWTU', scheduled.first.id
  end

  def test_scheduled_returns_empty_when_section_absent
    @mock_client.stub('users.customStatus.list', { 'ok' => true, 'statuses' => [] })

    assert_empty @api.scheduled
  end

  def test_schedule_sends_required_fields
    @mock_client.stub('users.customStatus.schedule', { 'ok' => true, 'scheduled_status' => scheduled_payload })

    @api.schedule(text: 'Vet Appt', emoji: ':paw_prints:', date_scheduled: 1_785_781_800)

    params = @mock_client.calls.last[:params]
    assert_equal 'users.customStatus.schedule', @mock_client.calls.last[:method]
    assert_equal 'Vet Appt', params[:text]
    assert_equal ':paw_prints:', params[:emoji]
    assert_equal '1785781800', params[:date_scheduled]
  end

  def test_schedule_includes_expiry_when_given
    @mock_client.stub('users.customStatus.schedule', { 'ok' => true, 'scheduled_status' => scheduled_payload })

    @api.schedule(text: 'Vet Appt', emoji: ':paw_prints:',
                  date_scheduled: 1_785_781_800, date_expire: 1_785_789_000)

    assert_equal '1785789000', @mock_client.calls.last[:params][:date_expire]
  end

  def test_schedule_omits_expiry_when_absent
    @mock_client.stub('users.customStatus.schedule', { 'ok' => true, 'scheduled_status' => scheduled_payload })

    @api.schedule(text: 'Vet Appt', emoji: ':paw_prints:', date_scheduled: 1_785_781_800)

    refute @mock_client.calls.last[:params].key?(:date_expire)
  end

  def test_schedule_sends_dnd_only_when_enabled
    @mock_client.stub('users.customStatus.schedule', { 'ok' => true, 'scheduled_status' => scheduled_payload })

    @api.schedule(text: 'Heads down', emoji: ':no_bell:', date_scheduled: 1, dnd: true)
    assert_equal 'true', @mock_client.calls.last[:params][:is_dnd]

    @api.schedule(text: 'Heads down', emoji: ':no_bell:', date_scheduled: 1)
    refute @mock_client.calls.last[:params].key?(:is_dnd)
  end

  def test_schedule_returns_the_created_model
    @mock_client.stub('users.customStatus.schedule', { 'ok' => true, 'scheduled_status' => scheduled_payload })

    result = @api.schedule(text: 'Vet Appt', emoji: ':paw_prints:', date_scheduled: 1_785_781_800)

    assert_instance_of Slk::Models::ScheduledStatus, result
    assert_equal 'CS0BMQDDGWTU', result.id
  end

  def test_delete_scheduled_sends_the_id
    @mock_client.stub('users.customStatus.deleteScheduled', { 'ok' => true })

    @api.delete_scheduled('CS0BMQDDGWTU')

    call = @mock_client.calls.last
    assert_equal 'users.customStatus.deleteScheduled', call[:method]
    assert_equal 'CS0BMQDDGWTU', call[:params][:custom_status_id]
  end
end
