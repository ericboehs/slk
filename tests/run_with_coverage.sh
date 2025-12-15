#!/usr/bin/env bash
# Run tests with code coverage using bashcov
# bashcov uses simplecov for Ruby-style coverage reports

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
COVERAGE_DIR="$PROJECT_DIR/coverage"
SLACK_CLI="$PROJECT_DIR/bin/slack"

# Clean previous coverage
rm -rf "$COVERAGE_DIR"
mkdir -p "$COVERAGE_DIR"

# Set up test environment
export TEST_CONFIG_DIR="/tmp/slack-cli-coverage-test"
export XDG_CONFIG_HOME="$TEST_CONFIG_DIR"
export XDG_CACHE_HOME="$TEST_CONFIG_DIR/cache"
export MOCK_PORT="${MOCK_PORT:-8089}"
export SLACK_API_BASE="http://localhost:$MOCK_PORT/api"

# Create test tokens
mkdir -p "$TEST_CONFIG_DIR/slack-cli"
cat > "$TEST_CONFIG_DIR/slack-cli/tokens.json" << 'EOF'
{"testworkspace": {"token": "xoxc-test", "cookie": "xoxd-test"}}
EOF
cat > "$TEST_CONFIG_DIR/slack-cli/config.json" << 'EOF'
{"primary_workspace": "testworkspace"}
EOF

# Start mock server
pkill -f mock_server.rb 2>/dev/null || true
ruby "$SCRIPT_DIR/mock_server.rb" &>/dev/null &
MOCK_PID=$!
sleep 3

echo "Running coverage tests with bashcov..."
echo ""

# Create a wrapper script that runs all commands
WRAPPER="$TEST_CONFIG_DIR/run_commands.sh"
cat > "$WRAPPER" << 'WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail

SLACK_CLI="$1"

# Help commands (covers argument parsing and help display)
"$SLACK_CLI" --version || true
"$SLACK_CLI" help || true
"$SLACK_CLI" status --help || true
"$SLACK_CLI" presence --help || true
"$SLACK_CLI" dnd --help || true
"$SLACK_CLI" messages --help || true
"$SLACK_CLI" unread --help || true
"$SLACK_CLI" catchup --help || true
"$SLACK_CLI" preset --help || true
"$SLACK_CLI" workspaces --help || true
"$SLACK_CLI" cache --help || true
"$SLACK_CLI" emoji --help || true

# API commands (will use mock server)
"$SLACK_CLI" status 2>/dev/null || true
"$SLACK_CLI" presence 2>/dev/null || true
"$SLACK_CLI" dnd 2>/dev/null || true
"$SLACK_CLI" unread 2>/dev/null || true
"$SLACK_CLI" preset list 2>/dev/null || true
"$SLACK_CLI" workspaces list 2>/dev/null || true
"$SLACK_CLI" cache list 2>/dev/null || true
WRAPPER_EOF
chmod +x "$WRAPPER"

# Run with bashcov (suppress trace output)
cd "$PROJECT_DIR"
bashcov --root "$PROJECT_DIR" -- "$WRAPPER" "$SLACK_CLI" 2>/dev/null || true

# Cleanup
kill $MOCK_PID 2>/dev/null || true
rm -rf "$TEST_CONFIG_DIR"

echo ""
echo "Coverage report: $COVERAGE_DIR/index.html"

# Extract and show coverage percentage for slack script only
if [[ -f "$COVERAGE_DIR/.resultset.json" ]]; then
  python3 -c "
import json
with open('$COVERAGE_DIR/.resultset.json') as f:
    data = json.load(f)
for run_name, run_data in data.items():
    for file_path, coverage in run_data.get('coverage', {}).items():
        if '/bin/slack' in file_path:
            covered = sum(1 for c in coverage if c is not None and c > 0)
            total = sum(1 for c in coverage if c is not None)
            if total > 0:
                percent = round(covered * 100 / total, 1)
                print(f'Lines covered: {covered}/{total} ({percent}%)')
"
fi

# Open in browser (optional)
if [[ "${OPEN_COVERAGE:-}" == "true" ]]; then
  open "$COVERAGE_DIR/index.html"
fi
