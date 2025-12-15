# Slack CLI

A comprehensive Bash CLI tool for managing Slack status, presence, notifications, and reading messages from the command line.

## Installation

```bash
# Clone the repo
git clone https://github.com/ericboehs/slack-cli.git
cd slack-cli

# Symlink to your bin directory
ln -s "$(pwd)/bin/slack" ~/bin/slack

# Run setup wizard
slack config
```

## Features

- **Status Management**: Set, get, and clear status with emoji and duration
- **Presets**: Define reusable status presets (meeting, lunch, focus, afk, brb, pto)
- **Presence**: Toggle between away/active presence
- **DND/Snooze**: Manage notification snoozing with durations
- **Messages**: Read messages from channels, DMs, and threads
- **Unread**: View and clear unread messages across channels
- **Catchup**: Interactive triage mode for unread messages
- **Threads**: View unread thread replies and mark them as read
- **Multi-workspace**: Support for multiple Slack workspaces
- **Emoji Support**: Standard Unicode emoji conversion + workspace custom emoji
- **Encrypted Storage**: Token encryption via age + SSH keys (optional)

## Running Tests

```bash
# Install dependencies
brew install bats-core

# Run all tests
bats tests/

# Run specific test file
bats tests/status.bats
```

## Test Architecture

Tests use a mock Slack API server (Ruby/Sinatra) that serves JSON fixtures:

```
tests/
├── mock_server.rb      # Mock API server
├── test_helper.bash    # Test utilities
├── status.bats         # Status command tests
└── fixtures/           # JSON response fixtures
    ├── users/
    │   ├── profile/get/default.json
    │   └── ...
    └── ...
```

Set scenarios for different test cases:
```bash
# In tests, use set_scenario to change API responses
set_scenario "users.profile.get" "no_status"
```

## License

MIT
