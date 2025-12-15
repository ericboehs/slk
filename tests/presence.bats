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

@test "slack presence shows current presence" {
  run "$SLACK_CLI" presence

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Auto"* ]] || [[ "$output" == *"online"* ]] || [[ "$output" == *"active"* ]]
}

@test "slack presence away sets presence to away" {
  run "$SLACK_CLI" presence away

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"away"* ]]
}

@test "slack presence auto sets presence to active" {
  run "$SLACK_CLI" presence auto

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"active"* ]] || [[ "$output" == *"auto"* ]]
}

@test "slack presence shows away when set" {
  set_scenario "users.getPresence" "away"

  run "$SLACK_CLI" presence

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Away"* ]] || [[ "$output" == *"away"* ]]
}
