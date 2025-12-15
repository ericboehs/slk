#!/usr/bin/env bash
# Test helper for slack-cli tests

# Paths
SLACK_CLI_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SLACK_CLI_DIR
export SLACK_CLI="$SLACK_CLI_DIR/bin/slack"
export FIXTURES_DIR="$SLACK_CLI_DIR/tests/fixtures"
export MOCK_SERVER="$SLACK_CLI_DIR/tests/mock_server.rb"

# Mock server settings
export MOCK_PORT="${MOCK_PORT:-8089}"
export SLACK_API_BASE="http://localhost:$MOCK_PORT/api"

# Test config directory (isolated from real config)
# Use a fixed location so it persists across setup_file and tests
export TEST_CONFIG_DIR="/tmp/slack-cli-tests"
export XDG_CONFIG_HOME="$TEST_CONFIG_DIR"
export XDG_CACHE_HOME="$TEST_CONFIG_DIR/cache"

# Mock server PID file
MOCK_PID_FILE="/tmp/slack-mock-server.pid"

# Create test token file
setup_test_tokens() {
  mkdir -p "$TEST_CONFIG_DIR/slack-cli"
  cat > "$TEST_CONFIG_DIR/slack-cli/tokens.json" << 'EOF'
{
  "testworkspace": {
    "token": "xoxc-test-token-12345",
    "cookie": "xoxd-test-cookie"
  }
}
EOF
}

# Create test config file
setup_test_config() {
  mkdir -p "$TEST_CONFIG_DIR/slack-cli"
  cat > "$TEST_CONFIG_DIR/slack-cli/config.json" << 'EOF'
{
  "primary_workspace": "testworkspace"
}
EOF
}

# Start mock server
start_mock_server() {
  if [[ -f "$MOCK_PID_FILE" ]]; then
    local pid
    pid=$(cat "$MOCK_PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      return 0  # Already running
    fi
  fi

  # Start server in background
  MOCK_PORT="$MOCK_PORT" ruby "$MOCK_SERVER" &>/dev/null &
  local pid=$!
  echo "$pid" > "$MOCK_PID_FILE"

  # Wait for server to be ready
  local max_attempts=30
  local attempt=0
  while ! curl -s "http://localhost:$MOCK_PORT/health" &>/dev/null; do
    sleep 0.1
    attempt=$((attempt + 1))
    if [[ $attempt -ge $max_attempts ]]; then
      echo "Mock server failed to start" >&2
      return 1
    fi
  done
}

# Stop mock server
stop_mock_server() {
  if [[ -f "$MOCK_PID_FILE" ]]; then
    local pid
    pid=$(cat "$MOCK_PID_FILE")
    kill "$pid" 2>/dev/null || true
    rm -f "$MOCK_PID_FILE"
  fi
}

# Set scenario for an API method
set_scenario() {
  local method="$1"
  local scenario="$2"
  curl -s -X POST "http://localhost:$MOCK_PORT/_test/scenario" \
    -H "Content-Type: application/json" \
    -d "{\"method\": \"$method\", \"scenario\": \"$scenario\"}" >/dev/null
}

# Reset all scenarios
reset_scenarios() {
  curl -s -X POST "http://localhost:$MOCK_PORT/_test/reset" >/dev/null
}

# Run slack CLI command
run_slack() {
  run "$SLACK_CLI" "$@"
}

# Common setup
setup_file() {
  setup_test_tokens
  setup_test_config
  start_mock_server
}

# Common teardown
teardown_file() {
  stop_mock_server
  rm -rf "$TEST_CONFIG_DIR"
}

# Per-test setup
setup() {
  reset_scenarios
}
