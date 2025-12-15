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

@test "slack cache shows help with --help" {
  run "$SLACK_CLI" cache --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
  [[ "$output" == *"cache"* ]]
}

@test "slack cache shows status" {
  run "$SLACK_CLI" cache

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"cache"* ]] || [[ "$output" == *"Cache"* ]]
}

@test "slack cache status shows cache info" {
  run "$SLACK_CLI" cache status

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
}

@test "slack cache populate fetches users" {
  run "$SLACK_CLI" cache populate

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
}

@test "slack cache clear removes cache" {
  # First populate the cache
  "$SLACK_CLI" cache populate 2>/dev/null || true

  run "$SLACK_CLI" cache clear

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
}
