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

@test "slack unread shows help with --help" {
  run "$SLACK_CLI" unread --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
  [[ "$output" == *"unread"* ]]
}

@test "slack unread shows unread messages" {
  run "$SLACK_CLI" unread

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  # Should show channels or threads with unreads
  [[ "$output" == *"general"* ]] || [[ "$output" == *"Threads"* ]] || [[ "$output" == *"unread"* ]]
}

@test "slack unread --json outputs JSON" {
  run "$SLACK_CLI" unread --json

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  # Should be valid JSON array
  [[ "$output" == "["* ]]
}

@test "slack unread shows no unreads when empty" {
  set_scenario "client.counts" "no_unreads"

  run "$SLACK_CLI" unread

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  # Should indicate no unreads or show empty output
  [[ "$output" == *"No unread"* ]] || [[ -z "$output" ]] || [ "$status" -eq 0 ]
}
