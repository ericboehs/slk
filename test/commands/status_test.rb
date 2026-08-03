# frozen_string_literal: true

require 'test_helper'

class StatusCommandTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @io = StringIO.new
    @err = StringIO.new
    @output = Slk::Formatters::Output.new(io: @io, err: @err, color: false)
  end

  def create_runner(workspaces: nil)
    # Create a mock token store
    token_store = Object.new
    workspace_list = workspaces || [mock_workspace('test')]

    token_store.define_singleton_method(:workspace) do |name|
      workspace_list.find { |w| w.name == name } || workspace_list.first
    end

    token_store.define_singleton_method(:all_workspaces) { workspace_list }
    token_store.define_singleton_method(:workspace_names) { workspace_list.map(&:name) }
    token_store.define_singleton_method(:empty?) { workspace_list.empty? }
    token_store.define_singleton_method(:on_warning=) { |_| nil }

    config = Object.new
    config.define_singleton_method(:primary_workspace) { workspace_list.first&.name }
    config.define_singleton_method(:emoji_dir) { nil }
    config.define_singleton_method(:on_warning=) { |_| nil }
    config.define_singleton_method(:[]) { |_| nil }

    preset_store = Object.new
    preset_store.define_singleton_method(:on_warning=) { |_| nil }

    Slk::Runner.new(
      output: @output,
      config: config,
      token_store: token_store,
      api_client: @mock_client,
      preset_store: preset_store
    )
  end

  def test_get_status_displays_status
    @mock_client.stub('users.profile.get', {
                        'ok' => true,
                        'profile' => {
                          'status_text' => 'Working',
                          'status_emoji' => ':computer:',
                          'status_expiration' => 0
                        }
                      })

    runner = create_runner
    command = Slk::Commands::Status.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'Working'
    assert_includes @io.string, ':computer:'
  end

  def test_get_status_shows_no_status_message
    @mock_client.stub('users.profile.get', {
                        'ok' => true,
                        'profile' => {
                          'status_text' => '',
                          'status_emoji' => '',
                          'status_expiration' => 0
                        }
                      })

    runner = create_runner
    command = Slk::Commands::Status.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, '(no status set)'
  end

  def test_set_status_calls_api
    @mock_client.stub('users.profile.set', { 'ok' => true })

    runner = create_runner
    command = Slk::Commands::Status.new(['Working from home', ':house:'], runner: runner)
    result = command.execute

    assert_equal 0, result

    call = @mock_client.calls.find { |c| c[:method] == 'users.profile.set' }
    assert call, 'Expected users.profile.set to be called'
    assert_equal 'Working from home', call[:params][:profile][:status_text]
    assert_equal ':house:', call[:params][:profile][:status_emoji]
  end

  def test_set_status_with_duration
    @mock_client.stub('users.profile.set', { 'ok' => true })

    runner = create_runner
    command = Slk::Commands::Status.new(['Meeting', ':calendar:', '1h'], runner: runner)
    result = command.execute

    assert_equal 0, result

    call = @mock_client.calls.find { |c| c[:method] == 'users.profile.set' }
    assert call
    # Should have expiration set
    assert call[:params][:profile][:status_expiration].positive?
  end

  def test_clear_status
    @mock_client.stub('users.profile.set', { 'ok' => true })

    runner = create_runner
    command = Slk::Commands::Status.new(['clear'], runner: runner)
    result = command.execute

    assert_equal 0, result

    call = @mock_client.calls.find { |c| c[:method] == 'users.profile.set' }
    assert call
    assert_equal '', call[:params][:profile][:status_text]
    assert_equal '', call[:params][:profile][:status_emoji]
  end

  def test_help_option
    runner = create_runner
    command = Slk::Commands::Status.new(['--help'], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, 'slk status'
    assert_includes @io.string, 'OPTIONS'
  end

  def test_api_error_returns_one
    # Make the API raise an error by redefining get
    api_client = Object.new
    api_client.define_singleton_method(:get) do |_workspace, _method, _params = {}|
      raise Slk::ApiError, 'channel_not_found'
    end
    api_client.define_singleton_method(:post) do |_workspace, _method, _params = {}|
      raise Slk::ApiError, 'channel_not_found'
    end

    runner = create_runner
    # Replace the api_client
    runner.instance_variable_set(:@api_client, api_client)

    command = Slk::Commands::Status.new([], runner: runner)
    result = command.execute

    assert_equal 1, result
    assert_includes @err.string, 'Failed'
  end

  def test_set_status_with_presence_option
    @mock_client.stub('users.profile.set', { 'ok' => true })
    @mock_client.stub('users.setPresence', { 'ok' => true })

    runner = create_runner
    command = Slk::Commands::Status.new(['Working', ':computer:', '-p', 'away'], runner: runner)
    result = command.execute

    assert_equal 0, result

    presence_call = @mock_client.calls.find { |c| c[:method] == 'users.setPresence' }
    assert presence_call
    assert_equal 'away', presence_call[:params][:presence]
  end

  def test_set_status_with_dnd_option
    @mock_client.stub('users.profile.set', { 'ok' => true })
    @mock_client.stub('dnd.setSnooze', { 'ok' => true, 'snooze_enabled' => true })

    runner = create_runner
    command = Slk::Commands::Status.new(['Focus', ':headphones:', '-d', '2h'], runner: runner)
    result = command.execute

    assert_equal 0, result

    dnd_call = @mock_client.calls.find { |c| c[:method] == 'dnd.setSnooze' }
    assert dnd_call
    assert_equal 120, dnd_call[:params][:num_minutes]
  end

  def test_set_status_with_dnd_off
    @mock_client.stub('users.profile.set', { 'ok' => true })
    @mock_client.stub('dnd.endSnooze', { 'ok' => true })

    runner = create_runner
    command = Slk::Commands::Status.new(['Working', ':computer:', '-d', 'off'], runner: runner)
    result = command.execute

    assert_equal 0, result

    dnd_call = @mock_client.calls.find { |c| c[:method] == 'dnd.endSnooze' }
    assert dnd_call
  end

  def test_unknown_option_returns_error
    runner = create_runner
    command = Slk::Commands::Status.new(['--invalid-option'], runner: runner)
    result = command.execute

    assert_equal 1, result
    assert_includes @err.string, 'Unknown option'
    assert_includes @err.string, '--invalid-option'
  end

  def test_known_options_are_accepted
    @mock_client.stub('users.profile.set', { 'ok' => true })
    @mock_client.stub('users.setPresence', { 'ok' => true })

    runner = create_runner
    # Test valid options -p and -d
    command = Slk::Commands::Status.new(['Working', '-p', 'away'], runner: runner)
    result = command.execute

    assert_equal 0, result
    refute_includes @err.string, 'Unknown option'
  end

  def test_set_status_default_emoji_when_none_provided
    @mock_client.stub('users.profile.set', { 'ok' => true })
    runner = create_runner
    Slk::Commands::Status.new(['Lunch'], runner: runner).execute
    call = @mock_client.calls.find { |c| c[:method] == 'users.profile.set' }
    assert_equal ':speech_balloon:', call[:params][:profile][:status_emoji]
  end

  def test_get_status_with_explicit_workspace_option
    @mock_client.stub('users.profile.get', { 'ok' => true,
                                             'profile' => { 'status_text' => '', 'status_emoji' => '' } })
    runner = create_runner(workspaces: [mock_workspace('one'), mock_workspace('two')])
    Slk::Commands::Status.new(['-w', 'one'], runner: runner).execute
    refute_includes @io.string, 'two'
  end

  def test_get_status_multi_workspace_shows_workspace_label
    @mock_client.stub('users.profile.get', { 'ok' => true,
                                             'profile' => { 'status_text' => 'Hi',
                                                            'status_emoji' => ':wave:' } })
    runner = create_runner(workspaces: [mock_workspace('one'), mock_workspace('two')])
    Slk::Commands::Status.new([], runner: runner).execute
    assert_includes @io.string, 'one'
    assert_includes @io.string, 'two'
  end

  def test_set_status_presence_active_translates_to_auto
    @mock_client.stub('users.profile.set', { 'ok' => true })
    @mock_client.stub('users.setPresence', { 'ok' => true })
    runner = create_runner
    Slk::Commands::Status.new(['Working', '-p', 'active'], runner: runner).execute
    presence_call = @mock_client.calls.find { |c| c[:method] == 'users.setPresence' }
    assert_equal 'auto', presence_call[:params][:presence]
  end

  def test_show_all_workspaces_hint_with_multiple
    @mock_client.stub('users.profile.set', { 'ok' => true })
    runner = create_runner(workspaces: [mock_workspace('a'), mock_workspace('b')])
    Slk::Commands::Status.new(['Hello'], runner: runner).execute
    assert_match(/--all/, @io.string)
  end

  def test_show_all_workspaces_hint_skipped_with_workspace
    @mock_client.stub('users.profile.set', { 'ok' => true })
    runner = create_runner(workspaces: [mock_workspace('a'), mock_workspace('b')])
    Slk::Commands::Status.new(['Hello', '-w', 'a'], runner: runner).execute
    refute_match(/Tip/, @io.string)
  end

  def test_clear_with_workspace_filter
    @mock_client.stub('users.profile.set', { 'ok' => true })
    runner = create_runner(workspaces: [mock_workspace('a'), mock_workspace('b')])
    Slk::Commands::Status.new(['clear', '-w', 'a'], runner: runner).execute
    # Successfully cleared
    assert_includes @io.string, 'cleared'
  end

  def test_display_status_with_inline_image_when_supported
    Dir.mktmpdir do |dir|
      emoji_dir = File.join(dir, 'test')
      FileUtils.mkdir_p(emoji_dir)
      File.binwrite(File.join(emoji_dir, 'computer.png'), "\x89PNG\r\n\n#{'a' * 80}")

      @mock_client.stub('users.profile.get', {
                          'ok' => true,
                          'profile' => {
                            'status_text' => 'Coding', 'status_emoji' => ':computer:',
                            'status_expiration' => Time.now.to_i + 3600
                          }
                        })
      runner = create_runner
      runner.config.define_singleton_method(:emoji_dir) { dir }
      command = Slk::Commands::Status.new([], runner: runner)
      command.stub(:inline_images_supported?, true) do
        command.stub(:print_inline_image_with_text, ->(_p, _t, **_o) { true }) do
          command.execute
        end
      end
    end
  end

  def test_find_workspace_emoji_returns_nil_for_empty_emoji
    runner = create_runner
    command = Slk::Commands::Status.new([], runner: runner)
    assert_nil command.send(:find_workspace_emoji, 'test', '')
  end

  def test_find_workspace_emoji_returns_nil_when_dir_missing
    runner = create_runner
    command = Slk::Commands::Status.new([], runner: runner)
    runner.config.define_singleton_method(:emoji_dir) { '/no/such/path' }
    assert_nil command.send(:find_workspace_emoji, 'test', 'foo')
  end

  def test_print_status_with_image_text_only
    runner = create_runner
    command = Slk::Commands::Status.new([], runner: runner)
    captured = []
    command.stub(:print_inline_image_with_text, ->(_p, t, **_o) { captured << t }) do
      status = Slk::Models::Status.new(text: '', emoji: ':a:', expiration: 0)
      command.send(:print_status_with_image, '/tmp/img.png', status)
    end
    refute_includes captured.first, '('
  end

  def test_print_status_with_image_text_and_remaining
    runner = create_runner
    command = Slk::Commands::Status.new([], runner: runner)
    captured = []
    command.stub(:print_inline_image_with_text, ->(_p, t, **_o) { captured << t }) do
      status = Slk::Models::Status.new(text: 'Working', emoji: ':a:', expiration: Time.now.to_i + 3600)
      command.send(:print_status_with_image, '/tmp/img.png', status)
    end
    assert_match(/Working/, captured.first)
    assert_match(/\(/, captured.first)
  end

  # --- scheduling -----------------------------------------------------------

  def scheduled_payload(overrides = {})
    {
      'id' => 'CS0BMQDDGWTU',
      'text' => 'Vet Appt',
      'emoji' => ':paw_prints:',
      'is_dnd' => false,
      'is_active' => false,
      'date_scheduled' => Time.new(2026, 8, 3, 13, 30, 0).to_i,
      'date_expire' => Time.new(2026, 8, 3, 15, 30, 0).to_i
    }.merge(overrides)
  end

  def stub_schedule
    @mock_client.stub('users.customStatus.schedule',
                      { 'ok' => true, 'scheduled_status' => scheduled_payload })
  end

  def run_status(args, runner: nil)
    command = Slk::Commands::Status.new(args, runner: runner || create_runner)
    [command.execute, @mock_client.calls.last]
  end

  # Simulates one workspace rejecting the call while the others succeed.
  def fail_on_workspace(name, message = 'too_many_scheduled_statuses')
    original = @mock_client.method(:post_form)
    @mock_client.define_singleton_method(:post_form) do |workspace, method, params = {}|
      raise Slk::ApiError, message if workspace.name == name

      original.call(workspace, method, params)
    end
  end

  def three_workspaces
    create_runner(workspaces: [mock_workspace('alpha'), mock_workspace('beta'), mock_workspace('gamma')])
  end

  def test_schedule_sends_parsed_window_to_the_api
    stub_schedule
    future = Time.now + (24 * 3600)
    date = future.strftime('%Y-%m-%d')

    result, call = run_status(['schedule', 'Vet Appt', ':paw_prints:', "#{date} 13:30-15:30"])

    assert_equal 0, result
    assert_equal 'users.customStatus.schedule', call[:method]
    assert_equal 'Vet Appt', call[:params][:text]
    assert_equal ':paw_prints:', call[:params][:emoji]
    assert_equal Time.new(future.year, future.month, future.day, 13, 30, 0).to_i.to_s,
                 call[:params][:date_scheduled]
    assert_equal Time.new(future.year, future.month, future.day, 15, 30, 0).to_i.to_s,
                 call[:params][:date_expire]
  end

  def test_schedule_accepts_a_bare_time_range
    stub_schedule

    result, call = run_status(['schedule', 'Vet Appt', ':paw_prints:', '1:30p-3:30p'])

    assert_equal 0, result
    assert_equal 'users.customStatus.schedule', call[:method]
  end

  def test_schedule_defaults_the_emoji
    stub_schedule

    _result, call = run_status(['schedule', 'Vet Appt', '1:30p-3:30p'])

    assert_equal ':speech_balloon:', call[:params][:emoji]
  end

  def test_schedule_passes_dnd_flag
    stub_schedule

    _result, call = run_status(['schedule', 'Heads down', ':no_bell:', '1:30p-3:30p', '--with-dnd'])

    assert_equal 'true', call[:params][:is_dnd]
  end

  def test_schedule_reports_the_created_status
    stub_schedule

    run_status(['schedule', 'Vet Appt', ':paw_prints:', '1:30p-3:30p'])

    assert_includes @io.string + @err.string, 'Vet Appt'
  end

  def test_schedule_without_text_errors
    result, = run_status(['schedule'])

    assert_equal 1, result
    assert_includes @err.string, 'Usage: slk status schedule'
  end

  def test_schedule_without_a_time_range_errors
    result, = run_status(['schedule', 'Vet Appt', ':paw_prints:'])

    assert_equal 1, result
    assert_includes @err.string, 'Missing time range'
  end

  # Not shaped like a range at all, so it never reaches the parser. The message
  # must still name what was rejected rather than claim the range was omitted.
  def test_schedule_with_an_unparseable_range_errors
    result, = run_status(['schedule', 'Vet Appt', ':paw_prints:', '99:99-100:00'])

    assert_equal 1, result
    assert_includes @err.string, 'Unrecognized argument: 99:99-100:00'
  end

  # Only YYYY-MM-DD parses. Accepting the range and dropping the date silently
  # scheduled the status for today instead.
  def test_schedule_rejects_an_unsupported_date_prefix
    result, = run_status(['schedule', 'OOO', ':palm_tree:', '8/4', '9:00-17:00'])

    assert_equal 1, result
    assert_includes @err.string, 'Unrecognized argument: 8/4 9:00-17:00'
    assert_empty @mock_client.calls
  end

  def test_schedule_rejects_trailing_junk_after_a_valid_range
    result, = run_status(['schedule', 'Vet Appt', ':paw_prints:', '1:30p-3:30p', 'GARBAGE'])

    assert_equal 1, result
    assert_includes @err.string, 'Unrecognized argument'
    assert_empty @mock_client.calls
  end

  # Range-shaped but out of range, so the parser raises and the command reports it.
  def test_schedule_with_an_invalid_hour_reports_the_parser_error
    result, = run_status(['schedule', 'Vet Appt', ':paw_prints:', '25:00-26:00'])

    assert_equal 1, result
    assert_includes @err.string, 'Invalid hour'
  end

  # The positional range shares one date between both times, so a multi-day
  # window is only reachable through the flags.
  def test_schedule_with_start_and_end_flags_spans_multiple_days
    stub_schedule

    result, call = run_status(['schedule', 'OOO', ':palm_tree:',
                               '--start', '2026-08-12 8a', '--end', '2026-08-14 17:00'])

    assert_equal 0, result
    assert_equal Time.new(2026, 8, 12, 8, 0, 0).to_i.to_s, call[:params][:date_scheduled]
    assert_equal Time.new(2026, 8, 14, 17, 0, 0).to_i.to_s, call[:params][:date_expire]
  end

  # ScheduledStatus and the API already model an absent expiry; the positional
  # range just had no way to ask for it.
  def test_schedule_without_end_flag_omits_the_expiry
    stub_schedule

    result, call = run_status(['schedule', 'Heads down', ':no_bell:', '--start', '2026-08-12 8a'])

    assert_equal 0, result
    assert_equal Time.new(2026, 8, 12, 8, 0, 0).to_i.to_s, call[:params][:date_scheduled]
    refute call[:params].key?(:date_expire)
  end

  def test_schedule_rejects_end_flag_without_start
    result, = run_status(['schedule', 'OOO', ':palm_tree:', '--end', '2026-08-14 17:00'])

    assert_equal 1, result
    assert_includes @err.string, '--end requires --start'
    assert_empty @mock_client.calls
  end

  def test_schedule_rejects_mixing_a_range_with_the_flags
    result, = run_status(['schedule', 'OOO', ':palm_tree:', '1:30p-3:30p', '--start', '2026-08-12 8a'])

    assert_equal 1, result
    assert_includes @err.string, 'not both'
    assert_empty @mock_client.calls
  end

  # An explicit end is unambiguous, so a backwards window is an error rather
  # than something to roll forward a day.
  def test_schedule_rejects_end_before_start
    result, = run_status(['schedule', 'OOO', ':palm_tree:',
                          '--start', '2026-08-14 17:00', '--end', '2026-08-12 8a'])

    assert_equal 1, result
    assert_includes @err.string, 'is not after --start'
    assert_empty @mock_client.calls
  end

  def test_schedule_reports_an_unparseable_start_flag
    result, = run_status(['schedule', 'OOO', ':palm_tree:', '--start', 'next tuesday'])

    assert_equal 1, result
    assert_includes @err.string, 'Invalid time: next tuesday'
    assert_empty @mock_client.calls
  end

  # Aborting the loop would leave the user re-running to fix the tail, which
  # double-schedules every workspace that already succeeded.
  def test_schedule_continues_past_a_failing_workspace
    stub_schedule
    runner = three_workspaces
    fail_on_workspace('beta')

    result, = run_status(['schedule', 'Vet Appt', ':paw_prints:', '1:30p-3:30p', '--all'], runner: runner)

    assert_equal 1, result
    assert_includes @io.string, 'Scheduled on alpha'
    assert_includes @io.string, 'Scheduled on gamma'
    assert_includes @err.string, 'beta: too_many_scheduled_statuses'
  end

  # `scheduled` lists every workspace, so an ID pasted back in may belong to a
  # non-primary one. Defaulting to primary failed with a bare Slack error.
  def test_unschedule_finds_the_workspace_owning_the_id
    runner = three_workspaces
    @mock_client.stub('users.customStatus.list',
                      { 'ok' => true, 'scheduled_statuses' => [scheduled_payload] })

    result, call = run_status(%w[unschedule CS0BMQDDGWTU], runner: runner)

    assert_equal 0, result
    assert_equal 'users.customStatus.deleteScheduled', call[:method]
    assert_equal 'alpha', call[:workspace]
    assert_includes @io.string, 'Cancelled scheduled status on alpha'
  end

  def test_unschedule_reports_an_id_no_workspace_owns
    runner = three_workspaces
    @mock_client.stub('users.customStatus.list', { 'ok' => true, 'scheduled_statuses' => [] })

    result, = run_status(%w[unschedule CSNOSUCHID], runner: runner)

    assert_equal 1, result
    assert_includes @err.string, 'No scheduled status CSNOSUCHID found'
    refute(@mock_client.calls.any? { |c| c[:method] == 'users.customStatus.deleteScheduled' })
  end

  # An explicit -w must not pay for the lookup or be overridden by it.
  def test_unschedule_with_workspace_flag_skips_the_owner_lookup
    runner = three_workspaces

    result, call = run_status(['unschedule', 'CS0BMQDDGWTU', '-w', 'gamma'], runner: runner)

    assert_equal 0, result
    assert_equal 'gamma', call[:workspace]
    refute(@mock_client.calls.any? { |c| c[:method] == 'users.customStatus.list' })
  end

  # A failed lookup must not masquerade as "not found".
  def test_unschedule_warns_when_a_workspace_cannot_be_checked
    runner = three_workspaces
    @mock_client.stub('users.customStatus.list',
                      { 'ok' => true, 'scheduled_statuses' => [scheduled_payload] })
    fail_on_workspace('alpha', 'ratelimited')

    result, = run_status(%w[unschedule CS0BMQDDGWTU], runner: runner)

    assert_equal 0, result
    assert_includes @err.string, 'Could not check alpha: ratelimited'
    assert_includes @io.string, 'Cancelled scheduled status on beta'
  end

  def test_unschedule_rejects_a_blank_id
    result, = run_status(['unschedule', '  '])

    assert_equal 1, result
    assert_includes @err.string, 'Usage: slk status unschedule'
    assert_empty @mock_client.calls
  end

  def test_unschedule_continues_past_a_failing_workspace
    runner = three_workspaces
    fail_on_workspace('beta', 'status_not_found')

    result, = run_status(['unschedule', 'CS0BMQDDGWTU', '--all'], runner: runner)

    assert_equal 1, result
    assert_includes @io.string, 'Cancelled scheduled status on gamma'
    assert_includes @err.string, 'beta: status_not_found'
  end

  # A Slack-side failure must not be reported as if the user mistyped the range.
  def test_schedule_reports_an_unconfirmed_response_as_an_api_failure
    @mock_client.stub('users.customStatus.schedule', { 'ok' => true })

    result, = run_status(['schedule', 'Vet Appt', ':paw_prints:', '1:30p-3:30p'])

    assert_equal 1, result
    assert_includes @err.string, 'returned no scheduled status'
  end

  def test_scheduled_lists_pending_statuses
    @mock_client.stub('users.customStatus.list',
                      { 'ok' => true, 'scheduled_statuses' => [scheduled_payload] })

    result, = run_status(['scheduled'])

    assert_equal 0, result
    assert_includes @io.string, 'CS0BMQDDGWTU'
    assert_includes @io.string, 'Vet Appt'
  end

  def test_scheduled_reports_when_none_pending
    @mock_client.stub('users.customStatus.list', { 'ok' => true, 'scheduled_statuses' => [] })

    result, = run_status(['scheduled'])

    assert_equal 0, result
    assert_includes @io.string, '(none scheduled)'
  end

  def test_unschedule_deletes_by_id
    @mock_client.stub('users.customStatus.deleteScheduled', { 'ok' => true })

    result, call = run_status(%w[unschedule CS0BMQDDGWTU])

    assert_equal 0, result
    assert_equal 'users.customStatus.deleteScheduled', call[:method]
    assert_equal 'CS0BMQDDGWTU', call[:params][:custom_status_id]
  end

  def test_unschedule_without_id_errors
    result, = run_status(['unschedule'])

    assert_equal 1, result
    assert_includes @err.string, 'Usage: slk status unschedule'
  end

  # The scheduling keywords must not shadow ordinary status text.
  def test_plain_text_status_still_sets_status
    @mock_client.stub('users.profile.set', { 'ok' => true })

    _result, call = run_status(['Working', ':computer:'])

    assert_equal 'users.profile.set', call[:method]
  end
end
