# frozen_string_literal: true

require 'test_helper'

class HuddlesCommandTest < Minitest::Test
  def setup
    @output = test_output
    @workspace = mock_workspace('oddball')
    @mock_client = Slk::TestHelpers::PagedUsersClient.new([roster])
  end

  def test_lists_calls_grouped_by_call_id
    assert_equal 0, execute([])

    assert_includes io_string, '2 active huddles'
    assert_includes io_string, '#eert'
    assert_includes io_string, '  Ada Lovelace'
    assert_includes io_string, '  Grace Hopper'
    assert_includes io_string, 'Alex Teal, Jason Byrne'
    assert_includes io_string, 'channel unknown'
    refute_includes io_string, 'Pat Away'
  end

  def test_pages_the_roster_before_grouping
    @mock_client = Slk::TestHelpers::PagedUsersClient.new([
                                                            [member('U1', 'Ada', call_id: 'R1', channel_id: 'C1')],
                                                            [member('U2', 'Bea', call_id: 'R1', channel_id: 'C1')]
                                                          ])

    assert_equal 0, execute([])

    assert_includes io_string, '1 active huddle'
    assert_includes io_string, '  Ada'
    assert_includes io_string, '  Bea'
    assert_equal(['cursor-1'], list_calls.filter_map { |call| call[:params][:cursor] })
  end

  def test_names_a_dm_and_survives_a_failed_channel_lookup
    @mock_client = Slk::TestHelpers::PagedUsersClient.new([[
                                                            member('U1', 'Ada', call_id: 'R1', channel_id: 'D1'),
                                                            member('U2', 'Bea', call_id: 'R2', channel_id: 'Cmissing')
                                                          ]])
    @mock_client.stub('conversations.info', lambda { |params|
      raise Slk::ApiError, 'channel_not_found' unless params[:channel] == 'D1'

      { 'ok' => true, 'channel' => { 'id' => 'D1', 'is_im' => true } }
    })

    assert_equal 0, execute([])
    assert_includes io_string, 'DM'
    assert_includes io_string, 'Cmissing'
    refute_includes io_string, 'channel unknown'
  end

  def test_json_for_one_workspace_is_a_single_document
    assert_equal 0, execute(['--json'])

    document = JSON.parse(io_string)
    calls = document.fetch('huddles')
    assert_equal 'R1', calls.first['call_id']
    assert_equal '#eert', calls.first['channel']
    assert_equal(%w[U1 U2], calls.first['participants'].map { |person| person['id'] })
    assert_nil calls.last['channel_id']
    assert_equal(%w[UD89FFGNP U051AUMQSBG], calls.last['participants'].map { |person| person['id'] })
  end

  def test_empty_roster
    @mock_client = Slk::TestHelpers::PagedUsersClient.new([[member('U1', 'Ada', state: 'default_unset')]])

    assert_equal 0, execute([])
    assert_includes io_string, 'No active huddles.'
  end

  def test_quiet_suppresses_text
    assert_equal 0, execute(['--quiet'])
    assert_empty io_string
  end

  def test_primary_workspace_only_unless_all
    other = mock_workspace('dsva')
    @mock_client = workspace_client('oddball' => [member('U1', 'Ada', call_id: 'R1')],
                                    'dsva' => [member('U9', 'Quinn', call_id: 'R9')])

    assert_equal 0, execute([], workspaces: [@workspace, other])
    assert_includes io_string, '1 active huddle on oddball'
    assert_includes io_string, 'Ada'
    refute_includes io_string, 'Quinn'

    @output = test_output
    assert_equal 0, execute(['--all'], workspaces: [@workspace, other])
    assert_includes io_string, 'oddball'
    assert_includes io_string, 'dsva'
    assert_includes io_string, 'Quinn'
  end

  def test_json_for_several_workspaces_is_keyed_by_name
    other = mock_workspace('dsva')
    @mock_client = workspace_client('oddball' => [member('U1', 'Ada', call_id: 'R1')],
                                    'dsva' => [])

    assert_equal 0, execute(['--all', '--json'], workspaces: [@workspace, other])

    document = JSON.parse(io_string)
    assert_equal %w[oddball dsva], document.keys
    assert_equal 'R1', document.dig('oddball', 'huddles', 0, 'call_id')
    assert_empty document.dig('dsva', 'huddles')
  end

  def test_workspace_flag_limits_the_scan
    other = mock_workspace('dsva')
    @mock_client = workspace_client('oddball' => [member('U1', 'Ada', call_id: 'R1')],
                                    'dsva' => [member('U9', 'Quinn', call_id: 'R9')])

    assert_equal 0, execute(['-w', 'dsva'], workspaces: [@workspace, other])
    assert_includes io_string, 'Quinn'
    refute_includes io_string, 'Ada'
  end

  def test_unexpected_argument
    assert_equal 1, execute(['alex'])
    assert_includes err_string, 'Unexpected argument: alex'
  end

  def test_unknown_option
    assert_equal 1, execute(['--nope'])
    assert_includes err_string, 'Unknown option: --nope'
  end

  def test_api_error
    @mock_client = Slk::TestHelpers::MockApiClient.new
    @mock_client.stub('users.list', Slk::ApiError.new('missing_scope', code: :missing_scope))

    assert_equal 1, execute([])
    assert_includes err_string, 'missing_scope'
  end

  def test_verbose_logs_a_failed_channel_lookup
    @output = Slk::Formatters::Output.new(io: StringIO.new, err: StringIO.new, color: false, verbose: true)
    roster = [member('U1', 'Ada', call_id: 'R1', channel_id: 'Cmissing')]
    @mock_client = Slk::TestHelpers::PagedUsersClient.new([roster])
    @mock_client.stub('conversations.info', Slk::ApiError.new('channel_not_found', code: :channel_not_found))

    assert_equal 0, execute(['-v'])
    assert_includes err_string, 'channel_not_found'
  end

  def test_help
    assert_equal 0, execute(['--help'])
    assert_includes io_string, 'slk huddles'
    assert_includes io_string, 'call id'
    assert_includes io_string, '--all'
  end

  private

  def roster
    [
      member('U1', 'Ada Lovelace', call_id: 'R1', channel_id: 'C1'),
      member('U2', 'Grace Hopper', call_id: 'R1', channel_id: 'C1'),
      member('UD89FFGNP', 'Alex Teal', call_id: 'R0'),
      member('U051AUMQSBG', 'Jason Byrne', call_id: 'R0'),
      member('U4', 'Pat Away', state: 'available_for_huddle', call_id: 'R9')
    ]
  end

  def member(id, name, state: 'in_a_huddle', call_id: nil, channel_id: nil)
    {
      'id' => id,
      'real_name' => name,
      'profile' => {
        'display_name' => name,
        'real_name' => name,
        'huddle_state' => state,
        'huddle_state_call_id' => call_id,
        'huddle_state_channel_id' => channel_id
      }
    }
  end

  def execute(args, workspaces: [@workspace])
    stub_channel_name
    Slk::Commands::Huddles.new(args, runner: runner(workspaces)).execute
  end

  def stub_channel_name
    return if @mock_client.instance_variable_get(:@responses)['conversations.info']

    @mock_client.stub('conversations.info', {
                        'ok' => true,
                        'channel' => { 'id' => 'C1', 'name' => 'eert' }
                      })
  end

  def runner(workspaces)
    cache = Slk::Services::CacheStore.new(paths: temp_paths)
    built = Slk::Runner.new(output: @output, api_client: @mock_client, cache_store: cache)
    built.define_singleton_method(:workspace) do |name = nil|
      workspaces.find { |workspace| workspace.name == name } || workspaces.first
    end
    built.define_singleton_method(:all_workspaces) { workspaces }
    built
  end

  def workspace_client(rosters)
    client = Slk::TestHelpers::MockApiClient.new
    client.define_singleton_method(:post) do |workspace, method, params = {}|
      @calls << { workspace: workspace.name, method: method, params: params }
      if method == 'users.list'
        { 'ok' => true, 'members' => rosters[workspace.name] || [],
          'response_metadata' => { 'next_cursor' => '' } }
      else
        response = @responses[method] || { 'ok' => true }
        response = response.call(params) if response.respond_to?(:call)
        raise response if response.is_a?(Exception)

        response
      end
    end
    client
  end

  def temp_paths
    @temp_paths ||= Slk::TestHelpers::TempPaths.new
  end

  def io_string = @output.instance_variable_get(:@io).string

  def err_string = @output.instance_variable_get(:@err).string

  def list_calls
    @mock_client.calls.select { |call| call[:method] == 'users.list' }
  end
end
