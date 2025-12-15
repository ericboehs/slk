#!/usr/bin/env bats

load 'test_helper'

setup_file() {
  pkill -f "mock_server.rb" 2>/dev/null || true
  rm -rf /tmp/slack-cli-tests 2>/dev/null || true

  export TEST_CONFIG_DIR="/tmp/slack-cli-tests"
  export XDG_CONFIG_HOME="$TEST_CONFIG_DIR"
  export XDG_CACHE_HOME="$TEST_CONFIG_DIR/cache"
  export SLACK_API_BASE="http://localhost:$MOCK_PORT/api"

  setup_test_tokens
  setup_test_config
  start_mock_server
}

teardown_file() {
  stop_mock_server
  rm -rf /tmp/slack-cli-tests 2>/dev/null || true
}

setup() {
  export TEST_CONFIG_DIR="/tmp/slack-cli-tests"
  export XDG_CONFIG_HOME="$TEST_CONFIG_DIR"
  export XDG_CACHE_HOME="$TEST_CONFIG_DIR/cache"
  export SLACK_API_BASE="http://localhost:$MOCK_PORT/api"
  reset_scenarios 2>/dev/null || true
}

@test "slack with unknown command shows error" {
  run "$SLACK_CLI" unknowncommand123

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown"* ]] || [[ "$output" == *"unknown"* ]] || [[ "$output" == *"command"* ]]
}

@test "slack status with unknown option shows error" {
  run "$SLACK_CLI" status --unknown-option-xyz

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Unknown"* ]] || [[ "$output" == *"unknown"* ]]
}

@test "slack messages without target shows error or help" {
  run "$SLACK_CLI" messages

  echo "Status: $status"
  echo "Output: $output"

  # Should either show error or help
  [ "$status" -ne 0 ] || [[ "$output" == *"USAGE"* ]]
}

@test "slack dnd with invalid duration format shows error" {
  run "$SLACK_CLI" dnd on "invalid_duration"

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -ne 0 ]
  [[ "$output" == *"Invalid duration"* ]]
}

@test "slack status handles API error gracefully" {
  set_scenario "users.profile.get" "api_error"

  run "$SLACK_CLI" status

  echo "Status: $status"
  echo "Output: $output"

  # Should fail with meaningful error
  [ "$status" -ne 0 ]
  [[ "$output" == *"error"* ]] || [[ "$output" == *"Error"* ]] || [[ "$output" == *"Failed"* ]]
}

@test "slack with -w nonexistent workspace shows error" {
  run "$SLACK_CLI" status -w nonexistent_workspace_xyz

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]] || [[ "$output" == *"Not found"* ]] || [[ "$output" == *"Unknown"* ]]
}
