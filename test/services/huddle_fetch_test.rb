# frozen_string_literal: true

require 'test_helper'

class HuddleFetchTest < Minitest::Test
  def test_one_workspace_uses_the_shared_client
    parent = RecordingClient.new
    oddball = workspace('oddball', [member('U1', 'Ada', call_id: 'R1')])
    reports = fetch(parent, [oddball])

    assert_equal ['oddball'], reports.map(&:workspace)
    names = reports.first.huddles.flat_map { |huddle| huddle.participants.map(&:name) }
    assert_equal ['Ada'], names
    assert_empty parent.children
    refute parent.closed?
  end

  def test_several_workspaces_each_get_a_connection_and_keep_order
    parent = RecordingClient.new
    workspaces = [
      workspace('oddball', [member('U1', 'Ada', call_id: 'R1'), member('U2', 'Pat', state: 'default_unset')]),
      workspace('dsva', [member('U9', 'Quinn', call_id: 'R9')])
    ]
    reports = fetch(parent, workspaces)

    assert_equal %w[oddball dsva], reports.map(&:workspace)
    names = reports.first.huddles.flat_map { |huddle| huddle.participants.map(&:name) }
    assert_equal ['Ada'], names
    assert_equal 2, parent.children.size
    assert parent.children.all?(&:closed?)
    refute parent.closed?
  end

  def test_a_failed_workspace_still_closes_its_connection
    parent = RecordingClient.new
    workspaces = [workspace('oddball', []), workspace('dsva', [], error: 'missing_scope')]

    error = assert_raises(Slk::ApiError) { fetch(parent, workspaces) }

    assert_equal 'missing_scope', error.message
    assert parent.children.all?(&:closed?)
  end

  def test_room_lookup_adds_channel_and_slack_connect_guests
    parent = RecordingClient.new
    rooms = { 'R1' => { 'channels' => ['C1'], 'participants' => %w[U1 UX] } }
    oddball = workspace('oddball', [member('U1', 'Ada', call_id: 'R1')], rooms: rooms)
    huddle = fetch(parent, [oddball]).first.huddles.first

    assert_equal 'C1', huddle.channel_id
    assert_equal '#eert', huddle.channel
    assert_equal %w[Ada Guest], huddle.participants.map(&:name)
  end

  def test_several_rooms_are_looked_up_on_a_worker_pool
    parent = RecordingClient.new
    rooms = {
      'R1' => { 'channels' => ['C1'], 'participants' => %w[U1 UX] },
      'R2' => { 'channels' => ['C1'], 'participants' => %w[U2 UX] }
    }
    roster = [member('U1', 'Ada', call_id: 'R1'), member('U2', 'Bo', call_id: 'R2')]
    huddles = fetch(parent, [workspace('oddball', roster, rooms: rooms)]).first.huddles

    assert_equal([%w[Ada Guest], %w[Bo Guest]], huddles.map { |huddle| huddle.participants.map(&:name) })
    refute_empty parent.children
    assert parent.children.all?(&:closed?)
  end

  def test_unauthorized_room_lookup_leaves_the_huddle_unplaced
    parent = RecordingClient.new
    oddball = workspace('oddball', [member('U1', 'Ada', call_id: 'R1')], rooms: {})
    huddle = fetch(parent, [oddball]).first.huddles.first

    assert_nil huddle.channel_id
    assert_equal ['Ada'], huddle.participants.map(&:name)
  end

  private

  def fetch(client, workspaces)
    runner = Struct.new(:api_client, :cache_store).new(client, cache)
    workspaces_by_name = workspaces.to_h { |ws| [ws.name, ws] }
    runner.define_singleton_method(:conversations_api) { |name| Slk::Api::Conversations.new(client, workspaces_by_name[name]) }
    Slk::Services::HuddleFetch.new(runner: runner, output: test_output).call(workspaces)
  end

  def cache
    Slk::Services::CacheStore.new(paths: Slk::TestHelpers::TempPaths.new)
  end

  def workspace(name, members, error: nil, rooms: {})
    Struct.new(:name, :roster, :error, :rooms).new(name, members, error, rooms)
  end

  def member(id, name, state: 'in_a_huddle', call_id: nil)
    {
      'id' => id,
      'profile' => {
        'display_name' => name,
        'huddle_state' => state,
        'huddle_state_call_id' => call_id
      }
    }
  end

  class RecordingClient
    attr_reader :children

    def initialize(parent = nil)
      @parent = parent
      @children = []
      @closed = false
      @mutex = Mutex.new
    end

    def isolated
      self.class.new(self).tap do |child|
        @mutex.synchronize { @children << child }
      end
    end

    def post(workspace, method, params = {})
      raise Slk::ApiError, workspace.error if workspace.error

      return { 'ok' => true, 'channel' => { 'name' => 'eert' } } if method == 'conversations.info'
      return room(workspace, params[:huddle_id]) if method == 'huddles.get'

      { 'ok' => true, 'members' => workspace.roster, 'response_metadata' => { 'next_cursor' => '' } }
    end

    def post_form(workspace, method, params = {})
      return post(workspace, method, params) unless method == 'users.info'

      { 'ok' => true, 'user' => { 'id' => params[:user], 'profile' => { 'display_name' => 'Guest' } } }
    end

    def room(workspace, id)
      room = workspace.rooms[id]
      raise Slk::ApiError, 'not_authorized' unless room

      { 'ok' => true, 'huddle' => room }
    end

    def close
      @closed = true
    end

    def closed? = @closed
  end
end
