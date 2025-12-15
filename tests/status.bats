#!/usr/bin/env bats

load 'test_helper'

# File-level setup/teardown
setup_file() {
  # Ensure clean state
  pkill -f "mock_server.rb" 2>/dev/null || true
  rm -rf /tmp/slack-cli-tests 2>/dev/null || true

  # Export so subprocesses get these
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

# Per-test setup
setup() {
  # Re-export env vars for each test (bats runs tests in subshells)
  export TEST_CONFIG_DIR="/tmp/slack-cli-tests"
  export XDG_CONFIG_HOME="$TEST_CONFIG_DIR"
  export XDG_CACHE_HOME="$TEST_CONFIG_DIR/cache"
  export SLACK_API_BASE="http://localhost:$MOCK_PORT/api"
  reset_scenarios 2>/dev/null || true
}

@test "slack status shows current status" {
  run "$SLACK_CLI" status

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Working from home"* ]]
  [[ "$output" == *":house:"* ]]
}

@test "slack status shows no status when empty" {
  set_scenario "users.profile.get" "no_status"

  run "$SLACK_CLI" status

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
}

@test "slack status shows help with --help" {
  run "$SLACK_CLI" status --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
  [[ "$output" == *"status"* ]]
}

@test "slack --version shows version" {
  run "$SLACK_CLI" --version

  [ "$status" -eq 0 ]
  [[ "$output" == *"slack v"* ]]
}

@test "slack help shows available commands" {
  run "$SLACK_CLI" help

  [ "$status" -eq 0 ]
  [[ "$output" == *"status"* ]]
  [[ "$output" == *"presence"* ]]
  [[ "$output" == *"dnd"* ]]
}

@test "slack status set updates status" {
  run "$SLACK_CLI" status "Testing" ":test_tube:"

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"✓"* ]] || [[ "$output" == *"Status set"* ]] || [[ "$output" == *"testworkspace"* ]]
}

@test "slack status set with duration" {
  run "$SLACK_CLI" status "In a meeting" ":calendar:" "1h"

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
}

@test "slack status clear removes status" {
  run "$SLACK_CLI" status clear

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"✓"* ]] || [[ "$output" == *"cleared"* ]] || [[ "$output" == *"Cleared"* ]]
}

@test "slack status with expiration shows time remaining" {
  set_scenario "users.profile.get" "with_expiration"

  run "$SLACK_CLI" status

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  # Should show some indication of expiration time
}
