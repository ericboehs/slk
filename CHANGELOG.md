# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.6.0] - 2026-04-27

### Added

- **`slk who [target]`** — compact teems-style profile card for self or any user
  - Targets: positional arg accepts `Uxxx`, display name, real name, or email; defaults to self
  - `--full` expands into Contact / People / About me sections matching the Slack web profile
  - `--json` emits the full Profile struct for piping
  - `--refresh` bypasses both the per-run memo and the on-disk meta cache
  - `--all` prints every match in turn; `--pick N` picks the Nth match non-interactively
  - Multi-match disambiguation: prints a numbered list on stderr and prompts on a TTY; non-TTY contexts raise instead of silently picking
  - Renders Slack Connect external users with a stripped layout (`external — <home workspace>`)
  - Marks deactivated accounts with a bold `deactivated account` tag (and `deactivated: true` in JSON)
  - Type-aware custom field rendering: `link` fields use OSC 8 hyperlinks with their `alt` label, `date` fields show "Jun 17, 2024 (1y 10mo ago)", `user` fields resolve one level (name + pronouns + title)
- **`slk org [target]`** — walks the supervisor chain upward from the target
  - `--depth N` caps traversal (default 5); cycle-safe via seen-set
  - Indented tree with `└─ ├─ │` glyphs; `← you` marker on whichever node is the authenticated user
- New `Api::Team` wrapper for `team.info` and `team.profile.get`, plus `Api::Users#profile_for(user_id, include_labels:)`
- `Services::ProfileResolver`, `ProfileBuilder`, `UserMatcher`, `UserPicker`, `WhoTargetResolver`, `MetaCache` services backing the new commands
- Hidden `slk debug profile <uid>` subcommand for inspecting raw profile/info/schema responses

### Changed

- `ApiError` now carries a typed `code` symbol (`:user_not_found`, `:ratelimited`, `:network_error`, `:unauthorized`, `:http_error`, `:invalid_json`, `:missing_scope`); `ApiClient` populates it on every raise
- `ProfileResolver` only swallows `:user_not_found` from `users.profile.get` (Slack Connect fallback to `users.info`); other API errors propagate so callers can surface them
- CI matrix now uses `bundler-cache` and runs `bundle exec rake test`; new `coverage` job enforces a 95/95 line/branch SimpleCov threshold
- Pinned `parallel < 2.0` in dev/test bundle to keep Ruby 3.2 compatible with current rubocop

### Fixed

- `slk org` no longer mislabels the wrong node with `← you` when invoked against a teammate — the marker now compares each node against the authenticated user id

## [0.5.0] - 2026-04-13

### Added

- **`--fetch-attachments` flag** - Download message files and attachment images to local cache
  - Downloads Slack files (authed) and public attachment images (Giphy, Tenor, etc.)
  - Cached to `~/.cache/slk/files/{workspace}/` with skip-on-rerun
  - Shows copyable local file paths in output: `[File: /path/to/file.png]`
  - Works with `messages`, `thread`, and `--threads` inline replies
  - Summary line when files are present: `9 files not downloaded. Use --fetch-attachments to download.`
  - Follows up to 3 redirect hops with relative URL resolution

### Changed

- Added `rubocop` as a dev dependency for linting

### Fixed

- **`thread` command** - Extracted `resolve_and_display_thread` to fix rubocop complexity warnings

## [0.4.2] - 2026-03-01

### Added

- **Ghostty/Kitty terminal support** - Inline emoji images now work in Ghostty and Kitty terminals
  - Uses Kitty graphics protocol with Unicode placeholders for proper tmux support
  - Images clear correctly with `clear` command (no floating artifacts)
  - Converts GIF/JPEG to PNG automatically (macOS only via `sips`)

- **`later` command** - View Slack's "Save for Later" items
  - Lists saved messages with content preview
  - Filter by state: `--completed`, `--in-progress`
  - `--counts` for summary statistics (total, overdue, with due dates)
  - `--no-content` to skip fetching message text
  - `--workspace-emoji` for inline custom emoji images
  - `--width N` to wrap text at N columns
  - `--no-wrap` to truncate messages to single line
  - `--json` output includes message content

### Changed

- New `TextProcessor` service centralizes text processing (HTML decode, mentions, emoji)
- New `MessageResolver` service extracted from activity command for reuse
- Refactored formatters to use shared TextProcessor

### Fixed

- **`thread` command** - Fixed fetching wrong message when using `slk thread <url>`
  - Now uses `conversations.replies` directly instead of `conversations.history` with limit 1
  - Previously could return the wrong message if newer messages existed in the channel
  - Tightened URL validation to reject non-message URLs (e.g. channel-only URLs) early

## [0.4.0] - 2026-01-30

### Added

- **Windows Support** - slk now runs on Windows
  - Uses `%APPDATA%` and `%LOCALAPPDATA%` for config/cache directories
  - Cross-platform command detection with `Open3.capture3`
  - Proper NTFS permission handling (skips `chmod` on Windows)
  - New `Support::Platform` module for OS-specific behavior
  - CI testing on Windows (Ruby 3.2, 3.3, 3.4, 4.0)

### Changed

- New `UserLookup` service consolidates duplicate user name resolution logic
- Removed ~65 lines of duplicated code from `MentionReplacer` and `MessageFormatter`

## [0.3.0] - 2026-01-16

### Added

- `-vv`/`--very-verbose` flag for detailed API debugging with timing and response bodies
- SSH key validation and token migration when keys change
- Public key validation (ensures it matches private key)
- `config unset` command for removing configuration values
- CI infrastructure with GitHub Actions (Ruby 3.2-4.0, macOS, Ubuntu)

### Changed

- Improved error handling throughout with comprehensive tests
- Better SSH key error messages with public key prompting
- Cache user lookups to reduce API calls
- Improved rate limit error messages

### Fixed

- Test output no longer leaks to stdout
- All rubocop offenses resolved

## [0.2.0] - 2025-01-15

### Added

- `--workspace-emoji` flag for messages command to display custom workspace emoji as inline images (experimental, requires iTerm2/WezTerm/Mintty)
- JSON output now includes resolved user and channel names for `messages`, `activity`, and `unread` commands

### Changed

- Config/cache directories renamed from `slack-cli` to `slk`
- Repository renamed from `slack-cli` to `slk`

### Fixed

- `error()` helper now returns exit code 1 for proper shell exit status

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

[0.5.0]: https://github.com/ericboehs/slk/releases/tag/v0.5.0
[0.4.2]: https://github.com/ericboehs/slk/releases/tag/v0.4.2
[0.4.0]: https://github.com/ericboehs/slk/releases/tag/v0.4.0
[0.3.0]: https://github.com/ericboehs/slk/releases/tag/v0.3.0
[0.2.0]: https://github.com/ericboehs/slk/releases/tag/v0.2.0
[0.1.0]: https://github.com/ericboehs/slk/releases/tag/v0.1.0
