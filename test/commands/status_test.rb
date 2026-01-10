# frozen_string_literal: true

require "test_helper"

class StatusCommandTest < Minitest::Test
  def setup
    @mock_client = MockApiClient.new
    @io = StringIO.new
    @err = StringIO.new
    @output = SlackCli::Formatters::Output.new(io: @io, err: @err, color: false)
  end

  def create_runner(workspaces: nil)
    # Create a mock token store
    token_store = Object.new
    workspace_list = workspaces || [mock_workspace("test")]

    token_store.define_singleton_method(:workspace) do |name|
      workspace_list.find { |w| w.name == name } || workspace_list.first
    end

    token_store.define_singleton_method(:all_workspaces) { workspace_list }
    token_store.define_singleton_method(:workspace_names) { workspace_list.map(&:name) }
    token_store.define_singleton_method(:empty?) { workspace_list.empty? }
    token_store.define_singleton_method(:on_warning=) { |_| }

    config = Object.new
    config.define_singleton_method(:primary_workspace) { workspace_list.first&.name }
    config.define_singleton_method(:emoji_dir) { nil }
    config.define_singleton_method(:on_warning=) { |_| }
    config.define_singleton_method(:[]) { |_| nil }

    preset_store = Object.new
    preset_store.define_singleton_method(:on_warning=) { |_| }

    SlackCli::Runner.new(
      output: @output,
      config: config,
      token_store: token_store,
      api_client: @mock_client,
      preset_store: preset_store
    )
  end

  def test_get_status_displays_status
    @mock_client.stub("users.profile.get", {
      "ok" => true,
      "profile" => {
        "status_text" => "Working",
        "status_emoji" => ":computer:",
        "status_expiration" => 0
      }
    })

    runner = create_runner
    command = SlackCli::Commands::Status.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, "Working"
    assert_includes @io.string, ":computer:"
  end

  def test_get_status_shows_no_status_message
    @mock_client.stub("users.profile.get", {
      "ok" => true,
      "profile" => {
        "status_text" => "",
        "status_emoji" => "",
        "status_expiration" => 0
      }
    })

    runner = create_runner
    command = SlackCli::Commands::Status.new([], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, "(no status set)"
  end

  def test_set_status_calls_api
    @mock_client.stub("users.profile.set", { "ok" => true })

    runner = create_runner
    command = SlackCli::Commands::Status.new(["Working from home", ":house:"], runner: runner)
    result = command.execute

    assert_equal 0, result

    call = @mock_client.calls.find { |c| c[:method] == "users.profile.set" }
    assert call, "Expected users.profile.set to be called"
    assert_equal "Working from home", call[:params][:profile][:status_text]
    assert_equal ":house:", call[:params][:profile][:status_emoji]
  end

  def test_set_status_with_duration
    @mock_client.stub("users.profile.set", { "ok" => true })

    runner = create_runner
    command = SlackCli::Commands::Status.new(["Meeting", ":calendar:", "1h"], runner: runner)
    result = command.execute

    assert_equal 0, result

    call = @mock_client.calls.find { |c| c[:method] == "users.profile.set" }
    assert call
    # Should have expiration set
    assert call[:params][:profile][:status_expiration] > 0
  end

  def test_clear_status
    @mock_client.stub("users.profile.set", { "ok" => true })

    runner = create_runner
    command = SlackCli::Commands::Status.new(["clear"], runner: runner)
    result = command.execute

    assert_equal 0, result

    call = @mock_client.calls.find { |c| c[:method] == "users.profile.set" }
    assert call
    assert_equal "", call[:params][:profile][:status_text]
    assert_equal "", call[:params][:profile][:status_emoji]
  end

  def test_help_option
    runner = create_runner
    command = SlackCli::Commands::Status.new(["--help"], runner: runner)
    result = command.execute

    assert_equal 0, result
    assert_includes @io.string, "slk status"
    assert_includes @io.string, "OPTIONS"
  end

  def test_api_error_returns_1
    # Make the API raise an error by redefining get
    api_client = Object.new
    api_client.define_singleton_method(:get) do |_workspace, _method, _params = {}|
      raise SlackCli::ApiError, "channel_not_found"
    end
    api_client.define_singleton_method(:post) do |_workspace, _method, _params = {}|
      raise SlackCli::ApiError, "channel_not_found"
    end

    runner = create_runner
    # Replace the api_client
    runner.instance_variable_set(:@api_client, api_client)

    command = SlackCli::Commands::Status.new([], runner: runner)
    result = command.execute

    assert_equal 1, result
    assert_includes @err.string, "Failed"
  end

  def test_set_status_with_presence_option
    @mock_client.stub("users.profile.set", { "ok" => true })
    @mock_client.stub("users.setPresence", { "ok" => true })

    runner = create_runner
    command = SlackCli::Commands::Status.new(["Working", ":computer:", "-p", "away"], runner: runner)
    result = command.execute

    assert_equal 0, result

    presence_call = @mock_client.calls.find { |c| c[:method] == "users.setPresence" }
    assert presence_call
    assert_equal "away", presence_call[:params][:presence]
  end

  def test_set_status_with_dnd_option
    @mock_client.stub("users.profile.set", { "ok" => true })
    @mock_client.stub("dnd.setSnooze", { "ok" => true, "snooze_enabled" => true })

    runner = create_runner
    command = SlackCli::Commands::Status.new(["Focus", ":headphones:", "-d", "2h"], runner: runner)
    result = command.execute

    assert_equal 0, result

    dnd_call = @mock_client.calls.find { |c| c[:method] == "dnd.setSnooze" }
    assert dnd_call
    assert_equal 120, dnd_call[:params][:num_minutes]
  end

  def test_set_status_with_dnd_off
    @mock_client.stub("users.profile.set", { "ok" => true })
    @mock_client.stub("dnd.endSnooze", { "ok" => true })

    runner = create_runner
    command = SlackCli::Commands::Status.new(["Working", ":computer:", "-d", "off"], runner: runner)
    result = command.execute

    assert_equal 0, result

    dnd_call = @mock_client.calls.find { |c| c[:method] == "dnd.endSnooze" }
    assert dnd_call
  end
end
