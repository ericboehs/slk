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

# Test command aliases

@test "slack msgs is alias for messages" {
  run "$SLACK_CLI" msgs --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"messages"* ]]
}

@test "slack snooze is alias for dnd" {
  run "$SLACK_CLI" snooze --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"dnd"* ]] || [[ "$output" == *"DND"* ]]
}

@test "slack ws is alias for workspaces" {
  run "$SLACK_CLI" ws list

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"testworkspace"* ]]
}

@test "slack preset name as direct command" {
  # Using preset name directly as command
  run "$SLACK_CLI" meeting

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
}

@test "slack version shows version" {
  run "$SLACK_CLI" version

  [ "$status" -eq 0 ]
  [[ "$output" == *"slack v"* ]]
}

@test "slack -V shows version" {
  run "$SLACK_CLI" -V

  [ "$status" -eq 0 ]
  [[ "$output" == *"slack v"* ]]
}

@test "slack -h shows help" {
  run "$SLACK_CLI" -h

  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
}
