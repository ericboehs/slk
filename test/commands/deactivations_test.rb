# frozen_string_literal: true

require 'test_helper'

class DeactivationsCommandTest < Minitest::Test
  def setup
    @mock_client = PagingMockClient.new
    @output = test_output
    @workspace = mock_workspace('test')
    @mock_client.stub_pages('users.list', [roster])
  end

  # users.list pages by cursor, so the stub hands back one page per call and
  # advertises the next cursor until it runs out.
  class PagingMockClient < Slk::TestHelpers::MockApiClient
    def initialize
      super
      @pages = {}
      @page_index = Hash.new(0)
    end

    def stub_pages(method, pages)
      @pages[method] = pages.dup
    end

    def post(workspace, method, params = {})
      pages = @pages[method]
      return super unless pages

      @calls << { workspace: workspace.name, method: method, params: params }
      index = @page_index[method]
      @page_index[method] += 1
      cursor = index + 1 < pages.size ? "cursor-#{index + 1}" : ''
      { 'ok' => true, 'members' => pages[index] || [], 'response_metadata' => { 'next_cursor' => cursor } }
    end
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
    @temp_paths ||= TempPaths.new
  end

  class TempPaths
    def initialize = @dir = Dir.mktmpdir('slk-deactivations-cmd-test')
    def cache_file(name) = File.join(@dir, name)
    def ensure_cache_dir = FileUtils.mkdir_p(@dir)
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
    @mock_client = PagingMockClient.new
    @mock_client.stub_pages('users.list', [roster + [old]])

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
    @mock_client = PagingMockClient.new
    @mock_client.stub_pages('users.list', [[long]])

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
    @mock_client = PagingMockClient.new
    @mock_client.stub('users.list', Slk::ApiError.new('missing_scope', code: :missing_scope))

    assert_equal 1, execute_with_args([])
  end

  def test_pagination_collects_every_page
    @mock_client = PagingMockClient.new
    @mock_client.stub_pages('users.list', [[roster[0]], [roster[1]], [roster[3]]])

    assert_equal 0, execute_with_args([])
    assert_includes io_string, 'Ann Archer'
    assert_includes io_string, 'Bob Barker'
    list_calls = @mock_client.calls.count { |c| c[:method] == 'users.list' }
    assert_equal 3, list_calls
  end
end
