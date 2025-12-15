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

@test "slack workspaces shows help with --help" {
  run "$SLACK_CLI" workspaces --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"USAGE"* ]]
  [[ "$output" == *"workspaces"* ]]
}

@test "slack workspaces list shows configured workspaces" {
  run "$SLACK_CLI" workspaces list

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"testworkspace"* ]]
}

@test "slack workspaces (no args) lists workspaces" {
  run "$SLACK_CLI" workspaces

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"testworkspace"* ]]
}

@test "slack workspaces primary shows primary workspace" {
  run "$SLACK_CLI" workspaces primary

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -eq 0 ]
  [[ "$output" == *"testworkspace"* ]]
}

@test "slack workspaces remove nonexistent fails" {
  run "$SLACK_CLI" workspaces remove nonexistent_workspace_xyz

  echo "Status: $status"
  echo "Output: $output"

  [ "$status" -ne 0 ]
  [[ "$output" == *"not found"* ]] || [[ "$output" == *"Not found"* ]] || [[ "$output" == *"does not exist"* ]]
}
