# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-01-14

Initial release of the Ruby rewrite. Pure Ruby, no external dependencies.

### Added

- **Commands**
  - `status` - Get or set your Slack status with emoji and duration
  - `presence` - Toggle between active/away presence
  - `dnd` - Manage Do Not Disturb (enable, disable, with duration)
  - `messages` - Read channel or DM messages with reactions and threads
  - `thread` - View message threads directly from URL
  - `unread` - View and clear unread messages across workspaces
  - `catchup` - Quick summary of mentions and DMs
  - `activity` - View recent workspace activity (mentions, reactions, threads)
  - `preset` - Define and apply status presets (status + presence + DND)
  - `workspaces` - Manage multiple Slack workspaces
  - `cache` - Manage user/channel name cache
  - `emoji` - Download and search workspace custom emoji
  - `config` - Interactive setup and configuration

- **Features**
  - Multi-workspace support with easy switching (`-w` flag or `--all`)
  - Encrypted token storage using `age` with SSH keys
  - XDG-compliant configuration directories
  - HTTP connection reuse for better performance
  - Inline emoji images in supported terminals (iTerm2, tmux)
  - Reaction timestamps showing when users reacted
  - Block Kit message rendering
  - User and channel mention resolution
  - Verbose mode (`-v`) for API call debugging
  - JSON output mode (`--json`) for scripting

- **Developer Experience**
  - 542 tests with 1082 assertions
  - Pure Ruby stdlib - no gem dependencies
  - Ruby 3.2+ with modern features (Data.define, pattern matching)

[0.1.0]: https://github.com/ericboehs/slack-cli/releases/tag/v0.1.0
