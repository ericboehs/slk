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

@test "slack dnd shows current status" {
  run "$SLACK_CLI" dnd

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"snoozed"* ]] || [[ "$output" == *"Not"* ]]
}

@test "slack dnd on snoozes notifications" {
  run "$SLACK_CLI" dnd on

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"snoozed"* ]] || [[ "$output" == *"Snoozed"* ]]
}

@test "slack dnd off resumes notifications" {
  run "$SLACK_CLI" dnd off

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"resumed"* ]] || [[ "$output" == *"Resumed"* ]]
}

@test "slack dnd on with duration snoozes for specified time" {
  run "$SLACK_CLI" dnd on 2h

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"snoozed"* ]] || [[ "$output" == *"2h"* ]]
}

@test "slack dnd shows snoozing status when active" {
  set_scenario "dnd.info" "snoozing"

  run "$SLACK_CLI" dnd

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Snoozed"* ]] || [[ "$output" == *"until"* ]]
}
