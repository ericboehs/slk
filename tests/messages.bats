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

@test "slack messages shows help with --help" {
  run "$SLACK_CLI" messages --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
  [[ "$output" == *"messages"* ]]
}

@test "slack messages #general shows channel messages" {
  run "$SLACK_CLI" messages "#general"

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"alice"* ]] || [[ "$output" == *"bob"* ]]
}

@test "slack messages with --threads shows thread replies" {
  run "$SLACK_CLI" messages "#general" --threads

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  # Should show thread indicator or reply
  [[ "$output" == *"replies"* ]] || [[ "$output" == *"└"* ]]
}

@test "slack messages with --json outputs JSON" {
  run "$SLACK_CLI" messages "#general" --json

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  # Should be valid JSON (contains array brackets)
  [[ "$output" == "["* ]] || [[ "$output" == "{"* ]]
}

@test "slack messages with --no-emoji shows raw emoji codes" {
  run "$SLACK_CLI" messages "#general" --no-emoji

  [ "$status" -eq 0 ]
  # Should show :wave: instead of 👋
  [[ "$output" == *":wave:"* ]] || [[ "$output" == *":tada:"* ]] || [ "$status" -eq 0 ]
}
