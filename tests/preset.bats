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

@test "slack preset shows help with --help" {
  run "$SLACK_CLI" preset --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
  [[ "$output" == *"preset"* ]]
}

@test "slack preset list shows available presets" {
  run "$SLACK_CLI" preset list

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"meeting"* ]]
  [[ "$output" == *"lunch"* ]]
  [[ "$output" == *"focus"* ]]
}

@test "slack preset (no args) lists presets" {
  run "$SLACK_CLI" preset

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"Available presets"* ]]
}

@test "slack preset meeting applies meeting preset" {
  run "$SLACK_CLI" preset meeting

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  # Should set status and maybe dnd
  [[ "$output" == *"meeting"* ]] || [[ "$output" == *"Status set"* ]] || [[ "$output" == *"✓"* ]]
}

@test "slack preset focus applies focus preset with presence and dnd" {
  run "$SLACK_CLI" preset focus

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  # Focus preset sets status + presence away + dnd
  [[ "$output" == *"away"* ]] || [[ "$output" == *"snoozed"* ]] || [[ "$output" == *"✓"* ]]
}

@test "slack preset nonexistent fails with error" {
  run "$SLACK_CLI" preset nonexistent_preset_xyz

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]]
}
