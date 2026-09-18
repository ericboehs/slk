# frozen_string_literal: true

require 'test_helper'

class DeactivationsCommandTest < Minitest::Test
  def setup
    @output = test_output
    @workspace = mock_workspace('test')
    @mock_client = Slk::TestHelpers::PagedUsersClient.new([roster])
  end

  def member(id, name:, real_name:, **attrs)
    days_ago = attrs.fetch(:days_ago, 1)
    {
      'id' => id, 'name' => name, 'deleted' => attrs.fetch(:deleted, false),
      'is_bot' => attrs.fetch(:bot, false), 'updated' => (Time.now - (days_ago * 86_400)).to_i,
      'profile' => { 'real_name' => real_name, 'title' => attrs[:title], 'email' => "#{name}@example.com" }
    }
  end

  def roster
    [
      member('U1', name: 'ann', real_name: 'Ann Archer', title: 'Engineer', deleted: true, days_ago: 2),
      member('U2', name: 'bob', real_name: 'Bob Barker', title: 'Designer', deleted: true, days_ago: 200),
      member('B1', name: 'deploybot', real_name: 'Deploy Bot', deleted: true, days_ago: 3, bot: true),
      member('U3', name: 'cat', real_name: 'Cat Carter', title: 'Engineer')
    ]
  end

  def runner
    cache_store = Slk::Services::CacheStore.new(paths: temp_paths)
    runner = Slk::Runner.new(output: @output, api_client: @mock_client, cache_store: cache_store)
    workspace = @workspace
    runner.define_singleton_method(:workspace) { |_name = nil| workspace }
    runner
  end

  def temp_paths
    @temp_paths ||= Slk::TestHelpers::TempPaths.new
  end

  def io_string = @output.instance_variable_get(:@io).string

  def execute_with_args(args)
    Slk::Commands::Deactivations.new(args, runner: runner).execute
  end

  def test_lists_people_newest_first_and_hides_bots
    assert_equal 0, execute_with_args([])

    assert_match(/Ann Archer.*Bob Barker/m, io_string)
    refute_includes io_string, 'Deploy Bot'
    assert_includes io_string, 'test: 2 deactivated accounts (1 active members)'
  end

  def test_bots_flag_includes_apps
    assert_equal 0, execute_with_args(['--bots'])

    assert_includes io_string, 'Deploy Bot'
  end

  def test_since_filters_by_positional_argument
    assert_equal 0, execute_with_args(['30d'])

    assert_includes io_string, 'Ann Archer'
    refute_includes io_string, 'Bob Barker'
    assert_includes io_string, 'deactivated since 30d'
  end

  def test_since_flag_matches_positional_form
    assert_equal 0, execute_with_args(['--since', '30d'])

    refute_includes io_string, 'Bob Barker'
  end

  def test_limit_truncates_and_says_so
    assert_equal 0, execute_with_args(['-n', '1'])

    assert_includes io_string, 'Ann Archer'
    refute_includes io_string, 'Bob Barker'
    assert_includes io_string, 'Showing 1 of 2'
  end

  def test_limit_zero_shows_everything
    assert_equal 0, execute_with_args(['-n', '0'])

    assert_includes io_string, 'Bob Barker'
    refute_includes io_string, 'Showing'
  end

  def test_grep_matches_title_case_insensitively
    assert_equal 0, execute_with_args(['--grep', 'engineer'])

    assert_includes io_string, 'Ann Archer'
    refute_includes io_string, 'Bob Barker'
  end

  def test_grep_with_no_matches_reports_empty
    assert_equal 0, execute_with_args(['--grep', 'plumber'])

    assert_includes io_string, 'No deactivations match.'
  end

  def test_chart_renders_month_buckets
    assert_equal 0, execute_with_args(['--chart', '--since', '400d'])

    assert_includes io_string, Time.now.strftime('%Y-%m')
    assert_includes io_string, '█'
  end

  # An all-time histogram of an old workspace is mostly scrollback, so a bare
  # --chart covers the last year only.
  def test_chart_without_since_covers_the_last_twelve_months
    old = member('U9', name: 'old', real_name: 'Olde Timer', deleted: true, days_ago: 800)
    @mock_client = Slk::TestHelpers::PagedUsersClient.new([roster + [old]])

    assert_equal 0, execute_with_args(['--chart'])
    refute_includes io_string, (Time.now - (800 * 86_400)).strftime('%Y-%m')
    assert_includes io_string, 'last 12 months'
  end

  def test_refresh_refetches_the_roster
    execute_with_args([])
    before = @mock_client.calls.count { |c| c[:method] == 'users.list' }
    execute_with_args(['--refresh'])
    after = @mock_client.calls.count { |c| c[:method] == 'users.list' }

    assert_equal before + 1, after
  end

  # A stale roster is the difference between "nobody left this week" and
  # "nobody left since the last time you asked", so the age is on screen.
  def test_cached_roster_reports_its_age
    seed_cache(fetched_at: Time.now.to_i - 7200)

    assert_equal 0, execute_with_args([])
    assert_includes io_string, 'roster cached 2h ago'
    assert_empty(@mock_client.calls.select { |c| c[:method] == 'users.list' })
  end

  def test_long_names_and_titles_are_truncated_to_the_width
    long = member('U9', name: 'verbose', deleted: true,
                        real_name: 'Bartholomew Cuthbert Fitzwilliam Montgomery',
                        title: 'Principal Distinguished Staff Engineer of Very Long Titles Indeed')
    @mock_client = Slk::TestHelpers::PagedUsersClient.new([[long]])

    assert_equal 0, execute_with_args(['--width', '60'])
    assert_includes io_string, '…'
    assert(io_string.lines.all? { |line| line.chomp.length <= 60 })
  end

  def seed_cache(fetched_at:)
    Slk::Services::CacheStore.new(paths: temp_paths).set_meta(
      'test', Slk::Services::DeactivationScanner::CACHE_KEY,
      { 'fetched_at' => fetched_at, 'member_count' => 1, 'human_count' => 1, 'active_count' => 0,
        'records' => [Slk::Models::Deactivation.from_api(roster.first).to_cache] }
    )
  end

  def test_json_output_is_machine_readable
    assert_equal 0, execute_with_args(['--json'])
    payload = JSON.parse(io_string)

    assert_equal 'test', payload['workspace']
    assert_equal 1, payload['active_members']
    assert_equal 2, payload['total_deactivated']
    ids = payload['deactivations'].map { |d| d['user_id'] }
    assert_equal %w[U1 U2], ids
    assert_equal 'Ann Archer', payload['deactivations'].first['real_name']
    refute payload['includes_bots']
  end

  def test_invalid_since_is_a_usage_error
    error = assert_raises(Slk::UsageError) { execute_with_args(['5q']) }

    assert_match(/Invalid date format/, error.message)
  end

  # `-n foo` used to reach to_i, become 0, and quietly mean "show everything".
  def test_non_numeric_limit_is_rejected_rather_than_meaning_all
    error = assert_raises(Slk::UsageError) { execute_with_args(['-n', 'foo']) }

    assert_match(/non-negative integer/, error.message)
  end

  def test_negative_limit_is_rejected
    assert_raises(Slk::UsageError) { execute_with_args(['-n', '-3']) }
  end

  def test_second_time_window_is_rejected_rather_than_ignored
    error = assert_raises(Slk::UsageError) { execute_with_args(%w[30d 90d]) }

    assert_match(/Unexpected argument: 90d/, error.message)
  end

  # The chart heading promises a window; the rows have to cover it, including
  # the months in which nobody left.
  def test_bare_chart_covers_all_twelve_months
    assert_equal 0, execute_with_args(['--chart'])
    months = io_string.scan(/^\d{4}-\d{2}/)

    assert_equal 12, months.size
    assert_equal Time.now.strftime('%Y-%m'), months.last
  end

  def test_explicit_since_is_not_truncated_to_twelve_months
    old = member('U9', name: 'old', real_name: 'Olde Timer', deleted: true, days_ago: 800)
    @mock_client = Slk::TestHelpers::PagedUsersClient.new([roster + [old]])

    assert_equal 0, execute_with_args(['--chart', '--since', '1000d'])
    months = io_string.scan(/^\d{4}-\d{2}/)

    assert_operator months.size, :>, 24
    assert_includes io_string, (Time.now - (800 * 86_400)).strftime('%Y-%m')
  end

  def test_quiet_months_draw_no_bar
    assert_equal 0, execute_with_args(['--chart'])
    quiet = io_string.lines.grep(/^\d{4}-\d{2}\s+0\b/)

    refute_empty quiet, 'expected at least one month with no departures'
    assert(quiet.none? { |line| line.include?('█') })
  end

  def test_chart_says_when_records_were_dropped_for_having_no_date
    undated = { 'id' => 'U9', 'name' => 'ghost', 'deleted' => true, 'updated' => 0, 'profile' => {} }
    @mock_client = Slk::TestHelpers::PagedUsersClient.new([[undated]])

    assert_equal 0, execute_with_args(['--chart'])
    assert_includes io_string, 'No deactivations match.'
    assert_includes io_string, '1 with no recorded date omitted'
  end

  def test_undated_records_are_not_flagged_without_a_window
    undated = { 'id' => 'U9', 'name' => 'ghost', 'deleted' => true, 'updated' => 0, 'profile' => {} }
    @mock_client = Slk::TestHelpers::PagedUsersClient.new([[undated]])

    assert_equal 0, execute_with_args([])
    refute_includes io_string, 'no recorded date'
    assert_includes io_string, 'unknown'
  end

  # "Nobody matched" is worth much less without how old the roster behind it is.
  def test_empty_result_still_reports_totals_and_cache_age
    seed_cache(fetched_at: Time.now.to_i - 7200)

    assert_equal 0, execute_with_args(['--grep', 'plumber'])
    assert_includes io_string, 'No deactivations match.'
    assert_includes io_string, '1 deactivated in all'
    assert_includes io_string, 'roster cached 2h ago'
  end

  def test_filtered_footer_reports_the_unfiltered_total
    assert_equal 0, execute_with_args(['--grep', 'engineer'])

    assert_includes io_string, '2 deactivated in all (of 3 accounts ever created)'
  end

  def test_json_with_bots_counts_and_flags_them
    assert_equal 0, execute_with_args(['--bots', '--json'])
    payload = JSON.parse(io_string)

    assert payload['includes_bots']
    assert_equal 3, payload['total_deactivated']
    assert_equal 3, payload['matched']
  end

  def test_json_reports_undated_departures_as_null
    undated = { 'id' => 'U9', 'name' => 'ghost', 'deleted' => true, 'updated' => 0, 'profile' => {} }
    @mock_client = Slk::TestHelpers::PagedUsersClient.new([[undated]])

    assert_equal 0, execute_with_args(['--json'])
    entry = JSON.parse(io_string)['deactivations'].first

    assert_nil entry['deactivated_on']
    assert_nil entry['deactivated_at']
  end

  def test_invalid_grep_pattern_is_a_usage_error
    assert_raises(Slk::UsageError) { execute_with_args(['--grep', '[']) }
  end

  def test_unknown_option_exits_nonzero
    assert_equal 1, execute_with_args(['--nope'])
  end

  def test_help_mentions_the_updated_field_caveat
    assert_equal 0, execute_with_args(['--help'])

    assert_includes io_string, 'slk deactivations'
    assert_includes io_string, '`updated`'
  end

  def test_api_errors_are_reported_not_raised
    @mock_client = Slk::TestHelpers::MockApiClient.new
    @mock_client.stub('users.list', Slk::ApiError.new('missing_scope', code: :missing_scope))

    assert_equal 1, execute_with_args([])
  end

  def test_pagination_collects_every_page
    @mock_client = Slk::TestHelpers::PagedUsersClient.new([[roster[0]], [roster[1]], [roster[3]]])

    assert_equal 0, execute_with_args([])
    assert_includes io_string, 'Ann Archer'
    assert_includes io_string, 'Bob Barker'
    list_calls = @mock_client.calls.count { |c| c[:method] == 'users.list' }
    assert_equal 3, list_calls
  end

  # --- tenure -------------------------------------------------------------

  FIELD_ID = 'Xf05START'

  def stub_start_dates(dates, field: FIELD_ID)
    schema = { 'ok' => true,
               'profile' => { 'fields' => [{ 'id' => FIELD_ID, 'label' => 'Start Date', 'type' => 'date' }] } }
    schema['profile']['fields'] = [] unless field
    @mock_client.stub('team.profile.get', schema)
    @mock_client.stub('users.profile.get', lambda { |params|
      value = dates[params[:user]]
      fields = value ? { FIELD_ID => { 'value' => value } } : {}
      { 'ok' => true, 'profile' => { 'fields' => fields } }
    })
  end

  def profile_calls = @mock_client.calls.count { |c| c[:method] == 'users.profile.get' }

  def stub_schema_only
    fields = [{ 'id' => FIELD_ID, 'label' => 'Start Date', 'type' => 'date' }]
    @mock_client.stub('team.profile.get', { 'ok' => true, 'profile' => { 'fields' => fields } })
  end

  def test_tenure_adds_a_column_of_how_long_each_person_stayed
    stub_start_dates({ 'U1' => (Time.now - (800 * 86_400)).strftime('%Y-%m-%d') })

    assert_equal 0, execute_with_args(['--tenure'])
    assert_match(/Ann Archer\s+2y \dmo/, io_string)
  end

  # A start date nobody filled in leaves the cell blank rather than guessing.
  def test_an_unknown_start_date_leaves_the_cell_empty
    stub_start_dates({ 'U1' => (Time.now - (400 * 86_400)).strftime('%Y-%m-%d') })

    assert_equal 0, execute_with_args(['--tenure'])
    assert_match(/Bob Barker\s+Designer/, io_string)
  end

  # The whole point of the flag's cost: it only pays for rows on screen.
  def test_only_the_displayed_rows_cost_a_lookup
    stub_start_dates({})

    assert_equal 0, execute_with_args(['-n', '1', '--tenure'])
    assert_equal 1, profile_calls
  end

  def test_a_second_run_uses_the_cached_start_dates
    stub_start_dates({ 'U1' => '2020-01-15', 'U2' => '2019-02-02' })
    execute_with_args(['--tenure'])
    before = profile_calls
    execute_with_args(['--tenure'])

    assert_equal before, profile_calls
  end

  def test_tenure_is_not_fetched_unless_asked_for
    stub_start_dates({ 'U1' => '2020-01-15' })

    assert_equal 0, execute_with_args([])
    assert_equal 0, profile_calls
  end

  # Better to say how long this will take than to let someone wonder whether
  # the terminal has hung.
  def test_a_long_lookup_warns_about_the_wait_first
    crowd = (1..9).map { |i| member("U#{i}0", name: "p#{i}", real_name: "Person #{i}", deleted: true) }
    @mock_client = Slk::TestHelpers::PagedUsersClient.new([crowd])
    stub_start_dates({})

    assert_equal 0, execute_with_args(['--tenure'])
    warning = @output.instance_variable_get(:@err).string

    assert_match(/Looking up 9 start dates/, warning)
    assert_match(/roughly \d+ minutes?\b/, warning)
    assert_match(/Interrupting is safe/, warning)
  end

  def test_a_short_lookup_does_not_warn
    stub_start_dates({ 'U1' => '2020-01-15' })

    assert_equal 0, execute_with_args(['--tenure'])
    refute_match(/Looking up/, @output.instance_variable_get(:@err).string)
  end

  def test_the_wait_estimate_is_plural_when_it_should_be
    crowd = (1..20).map { |i| member("U#{i}0", name: "p#{i}", real_name: "Person #{i}", deleted: true) }
    @mock_client = Slk::TestHelpers::PagedUsersClient.new([crowd])
    stub_start_dates({})

    assert_equal 0, execute_with_args(['-n', '0', '--tenure'])
    assert_match(/roughly \d+ minutes/, @output.instance_variable_get(:@err).string)
  end

  def test_a_workspace_without_the_field_says_so_instead_of_failing_obscurely
    stub_start_dates({}, field: nil)

    assert_equal 1, execute_with_args(['--tenure'])
    assert_match(/no "Start Date" profile field/, @output.instance_variable_get(:@err).string)
  end

  # A histogram has no row to hang a tenure on; refusing beats ignoring.
  def test_tenure_with_chart_is_a_usage_error
    error = assert_raises(Slk::UsageError) { execute_with_args(['--tenure', '--chart']) }

    assert_match(/nothing to add to --chart/, error.message)
  end

  def test_tenure_appears_in_json_only_when_requested
    stub_start_dates({ 'U1' => '2020-01-15' })
    execute_with_args(['--tenure', '--json'])
    entry = JSON.parse(io_string)['deactivations'].first

    assert_equal '2020-01-15', entry['started_on']
    assert_operator entry['tenure_months'], :>, 60
  end

  def test_json_omits_tenure_keys_without_the_flag
    execute_with_args(['--json'])
    entry = JSON.parse(io_string)['deactivations'].first

    refute entry.key?('started_on')
    refute entry.key?('tenure_months')
  end

  # --- csv ----------------------------------------------------------------

  def test_csv_has_a_header_and_one_row_per_match
    assert_equal 0, execute_with_args(['--csv'])
    lines = io_string.lines.map(&:chomp)

    assert_equal 'deactivated_on,user_id,handle,real_name,title,email,bot', lines.first
    assert_equal 3, lines.size
    assert_includes lines[1], 'Ann Archer'
  end

  # A truncated export is a wrong answer that looks like a right one.
  def test_csv_ignores_the_row_limit
    assert_equal 0, execute_with_args(['-n', '1', '--csv'])

    assert_equal 3, io_string.lines.size
  end

  def test_csv_gains_tenure_columns_with_the_flag
    stub_start_dates({ 'U1' => '2020-01-15' })

    assert_equal 0, execute_with_args(['--tenure', '--csv'])
    lines = io_string.lines.map(&:chomp)

    assert_equal 'deactivated_on,user_id,handle,real_name,title,email,bot,started_on,tenure_months,tenure',
                 lines.first
    assert_includes lines[1], ',2020-01-15,'
  end

  def test_csv_leaves_unknown_tenure_cells_empty
    stub_start_dates({})

    assert_equal 0, execute_with_args(['--tenure', '--csv'])

    assert(io_string.lines[1].chomp.end_with?(',,,'))
  end

  def test_csv_quotes_a_title_containing_a_comma
    @mock_client = Slk::TestHelpers::PagedUsersClient.new(
      [[member('U9', name: 'zed', real_name: 'Zed Zane', title: 'Engineer, Senior', deleted: true)]]
    )

    assert_equal 0, execute_with_args(['--csv'])
    assert_includes io_string, '"Engineer, Senior"'
  end

  def test_csv_respects_filters
    assert_equal 0, execute_with_args(['--grep', 'designer', '--csv'])
    lines = io_string.lines.map(&:chomp)

    assert_equal 2, lines.size
    assert_includes lines[1], 'Bob Barker'
  end

  def test_csv_of_nothing_is_still_a_header
    assert_equal 0, execute_with_args(['--grep', 'plumber', '--csv'])

    assert_equal 1, io_string.lines.size
  end

  # --- what the export and the failure paths owe the caller ----------------

  # The flag's asymmetry is deliberate, so pin it: the export pays for every
  # matched row, not just the screenful -n would print.
  def test_csv_and_tenure_together_look_up_every_exported_row
    stub_start_dates({})

    assert_equal 0, execute_with_args(['-n', '1', '--tenure', '--csv'])
    assert_equal 3, io_string.lines.size
    assert_equal 2, profile_calls
  end

  def test_a_failed_start_date_lookup_exits_cleanly
    stub_schema_only
    @mock_client.stub('users.profile.get', Slk::ApiError.new('missing_scope', code: :missing_scope))

    assert_equal 1, execute_with_args(['--tenure'])
    assert_match(/missing_scope/, @output.instance_variable_get(:@err).string)
  end

  def test_the_failure_names_the_account_it_was_looking_up
    stub_schema_only
    @mock_client.stub('users.profile.get', Slk::ApiError.new('user_not_found', code: :user_not_found))
    execute_with_args(['--tenure'])

    assert_match(/looking up U1/, @output.instance_variable_get(:@err).string)
  end

  # Redirecting stdout to a file must capture data and nothing else.
  def test_a_warned_about_export_keeps_stdout_pure
    crowd = (1..9).map { |i| member("U#{i}0", name: "p#{i}", real_name: "Person #{i}", deleted: true) }
    @mock_client = Slk::TestHelpers::PagedUsersClient.new([crowd])
    stub_start_dates({})

    assert_equal 0, execute_with_args(['--tenure', '--csv'])
    assert_match(/Looking up/, @output.instance_variable_get(:@err).string)
    assert(io_string.lines.all? { |line| line.count(',') == 9 })
  end

  # Two ways of asking for the same rows is one too many.
  def test_csv_with_json_is_a_usage_error
    error = assert_raises(Slk::UsageError) { execute_with_args(['--csv', '--json']) }

    assert_match(/pick one/, error.message)
  end

  # Nobody filled the field in for anyone: the column is not worth its width.
  def test_all_unknown_start_dates_drop_the_terminal_column
    stub_start_dates({})

    assert_equal 0, execute_with_args(['--tenure'])
    assert_match(/^2\d{3}-\d\d-\d\d  Ann Archer  Engineer$/, io_string)
  end

  # ...but the CSV keeps its columns, because a header that comes and goes
  # breaks whatever is parsing it.
  def test_all_unknown_start_dates_keep_the_csv_columns
    stub_start_dates({})

    assert_equal 0, execute_with_args(['--tenure', '--csv'])
    assert_equal 10, io_string.lines.first.count(',') + 1
  end

  # A cache that cannot be written costs speed next time, not the answers now.
  def test_an_unwritable_cache_warns_but_still_prints_the_tenure
    skip 'chmod does not prevent writes on Windows' if Gem.win_platform?

    stub_start_dates({ 'U1' => '2020-01-15' })
    FileUtils.chmod(0o500, temp_paths.dir)

    assert_equal 0, execute_with_args(['--tenure'])
    assert_match(/2\d+y|\dy/, io_string)
    assert_match(/Could not save the start date cache/, @output.instance_variable_get(:@err).string)
  ensure
    FileUtils.chmod(0o700, temp_paths.dir)
  end

  # --- tenure edge cases ---------------------------------------------------

  def test_json_carries_nulls_when_no_start_date_is_known
    stub_start_dates({})
    execute_with_args(['--tenure', '--json'])
    entry = JSON.parse(io_string)['deactivations'].first

    assert_nil entry['started_on']
    assert_nil entry['tenure_months']
  end

  # A start date after the departure is a data entry error, not a negative
  # tenure. The bad date stays visible; the length it cannot support does not.
  def test_a_start_date_after_the_departure_reads_as_unknown
    stub_start_dates({ 'U1' => (Time.now + (30 * 86_400)).strftime('%Y-%m-%d') })
    execute_with_args(['--tenure', '--json'])
    entry = JSON.parse(io_string)['deactivations'].first

    refute_nil entry['started_on']
    assert_nil entry['tenure_months']
  end

  def test_the_csv_keeps_a_backwards_start_date_and_blanks_the_length
    future = (Time.now + (30 * 86_400)).strftime('%Y-%m-%d')
    stub_start_dates({ 'U1' => future })
    execute_with_args(['--tenure', '--csv'])
    row = io_string.lines.find { |l| l.include?('Ann Archer') }.chomp

    assert_includes row, ",#{future},,"
    assert(row.end_with?(',,'))
  end

  def test_a_failing_team_schema_call_exits_cleanly
    @mock_client.stub('team.profile.get', Slk::ApiError.new('missing_scope', code: :missing_scope))

    assert_equal 1, execute_with_args(['--tenure'])
    assert_match(/missing_scope/, @output.instance_variable_get(:@err).string)
  end

  def test_a_deactivation_with_no_date_can_still_have_a_tenure_looked_up
    undated = member('U7', name: 'una', real_name: 'Una Dated', deleted: true)
    undated.delete('updated')
    @mock_client = Slk::TestHelpers::PagedUsersClient.new([[undated]])
    stub_start_dates({ 'U7' => '2020-01-15' })

    assert_equal 0, execute_with_args(['--tenure'])
    assert_includes io_string, 'Una Dated'
  end
end
