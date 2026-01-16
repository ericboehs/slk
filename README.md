# slk - Slack CLI

A command-line interface for Slack. Manage your status, presence, DND, read messages, and more from the terminal.

**Pure Ruby. No dependencies.**

## Installation

```bash
gem install slk
```

Requires Ruby 3.2+.

### Windows

```powershell
# Install Ruby (if needed) via RubyInstaller or Chocolatey
winget install RubyInstallerTeam.Ruby.3.3
# or: choco install ruby

# Install slk
gem install slk

# (Optional) Install age for encrypted token storage
choco install age.portable
```

Configuration is stored in `%APPDATA%\slk\` on Windows.

## Setup

Run the setup wizard:

```bash
slk config setup
```

You'll need a Slack token. Get one from:
- **User token (xoxp-)**: https://api.slack.com/apps → OAuth & Permissions
- **Bot token (xoxb-)**: Create a Slack App with bot scopes
- **Session token (xoxc-)**: Extract from browser (requires cookie too)

## Usage

### Status

```bash
slk status                              # Show current status
slk status "Working from home" :house:  # Set status with emoji
slk status "In a meeting" :calendar: 1h # Set status for 1 hour
slk status clear                        # Clear status
```

### Presence

```bash
slk presence              # Show current presence
slk presence away         # Set to away
slk presence active       # Set to active
```

### Do Not Disturb

```bash
slk dnd                   # Show DND status
slk dnd 1h                # Enable DND for 1 hour
slk dnd on 30m            # Enable DND for 30 minutes
slk dnd off               # Disable DND
```

### Messages

```bash
slk messages general            # Read channel messages
slk messages @username          # Read DM with user
slk messages general -n 50      # Show 50 messages
slk messages general --json     # Output as JSON
```

### Activity

```bash
slk activity              # Show recent activity feed
slk activity -n 50        # Show 50 items
slk activity -m           # Show message previews
slk activity --reactions  # Filter: reactions only
slk activity --mentions   # Filter: mentions only
slk activity --threads    # Filter: thread replies only
```

Displays your recent activity feed including:
- Reactions to your messages
- Mentions (@user, @channel, @here, etc.)
- Thread replies
- Bot messages (reminders, notifications)

Use `--show-messages` (or `-m`) to preview the actual message content for each activity.

### Unread

```bash
slk unread                # Show unread counts
slk unread clear          # Mark all as read
slk unread clear general  # Mark channel as read
```

### Catchup (Interactive Triage)

```bash
slk catchup               # Interactively review unread channels
slk catchup --batch       # Non-interactive, mark all as read
```

### Presets

```bash
slk preset list           # List all presets
slk preset meeting        # Apply preset
slk preset add            # Add new preset (interactive)
slk meeting               # Shortcut: use preset name as command
```

Built-in presets: `meeting`, `lunch`, `focus`, `brb`, `clear`

### Workspaces

```bash
slk workspaces list       # List configured workspaces
slk workspaces add        # Add a workspace
slk workspaces primary    # Show/set primary workspace
```

### Cache Management

```bash
slk cache status          # Show cache status
slk cache populate        # Pre-populate user cache
slk cache clear           # Clear all caches
```

### Global Options

```bash
-w, --workspace NAME   # Use specific workspace
--all                  # Apply to all workspaces
-v, --verbose          # Show debug output
-q, --quiet            # Suppress output
--json                 # Output as JSON (where supported)
```

## Multi-Workspace

Configure multiple workspaces and switch between them:

```bash
slk workspaces add                    # Add another workspace
slk status -w work                    # Check status on 'work' workspace
slk status "OOO" --all                # Set status on all workspaces
```

## Token Encryption

Optionally encrypt your tokens with [age](https://github.com/FiloSottile/age) using an SSH key:

```bash
slk config set ssh_key ~/.ssh/id_ed25519
```

Tokens will be stored encrypted in `~/.config/slk/tokens.age`.

## Configuration

Files are stored in XDG-compliant locations (or `%APPDATA%`/`%LOCALAPPDATA%` on Windows):

- **Config**: `~/.config/slk/` (Windows: `%APPDATA%\slk\`)
  - `config.json` - Settings
  - `tokens.json` or `tokens.age` - Workspace tokens
  - `presets.json` - Status presets
- **Cache**: `~/.cache/slk/` (Windows: `%LOCALAPPDATA%\slk\`)
  - `users-{workspace}.json` - User cache
  - `channels-{workspace}.json` - Channel cache

## Development

```bash
# Clone the repo
git clone https://github.com/ericboehs/slk.git
cd slk

# Run from source
ruby -Ilib bin/slk --version

# Run tests
rake test
```

### Releasing

1. Update version in `lib/slk/version.rb`
2. Update `CHANGELOG.md` (move Unreleased to new version, add date)
3. Commit: `git commit -am "Release vX.Y.Z"`
4. Release to RubyGems: `rake release`
5. Create GitHub Release: `gh release create vX.Y.Z --generate-notes`

## License

MIT License. See [LICENSE](LICENSE) for details.
