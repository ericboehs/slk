# Slack CLI

A command-line interface for Slack. Manage your status, presence, DND, read messages, and more from the terminal.

**Pure Ruby. No dependencies.**

## Installation

```bash
gem install slack-cli
```

Requires Ruby 3.2+.

## Setup

Run the setup wizard:

```bash
slack config setup
```

You'll need a Slack token. Get one from:
- **User token (xoxp-)**: https://api.slack.com/apps → OAuth & Permissions
- **Bot token (xoxb-)**: Create a Slack App with bot scopes
- **Session token (xoxc-)**: Extract from browser (requires cookie too)

## Usage

### Status

```bash
slack status                              # Show current status
slack status "Working from home" :house:  # Set status with emoji
slack status "In a meeting" :calendar: 1h # Set status for 1 hour
slack status clear                        # Clear status
```

### Presence

```bash
slack presence              # Show current presence
slack presence away         # Set to away
slack presence active       # Set to active
```

### Do Not Disturb

```bash
slack dnd                   # Show DND status
slack dnd 1h                # Enable DND for 1 hour
slack dnd on 30m            # Enable DND for 30 minutes
slack dnd off               # Disable DND
```

### Messages

```bash
slack messages #general           # Read channel messages
slack messages @username          # Read DM with user
slack messages #general -n 50     # Show 50 messages
slack messages #general --json    # Output as JSON
```

### Unread

```bash
slack unread                # Show unread counts
slack unread clear          # Mark all as read
slack unread clear #general # Mark channel as read
```

### Catchup (Interactive Triage)

```bash
slack catchup               # Interactively review unread channels
slack catchup --batch       # Non-interactive, mark all as read
```

### Presets

```bash
slack preset list           # List all presets
slack preset meeting        # Apply preset
slack preset add            # Add new preset (interactive)
slack meeting               # Shortcut: use preset name as command
```

Built-in presets: `meeting`, `lunch`, `focus`, `brb`, `clear`

### Workspaces

```bash
slack workspaces list       # List configured workspaces
slack workspaces add        # Add a workspace
slack workspaces primary    # Show/set primary workspace
```

### Cache Management

```bash
slack cache status          # Show cache status
slack cache populate        # Pre-populate user cache
slack cache clear           # Clear all caches
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
slack workspaces add                    # Add another workspace
slack status -w work                    # Check status on 'work' workspace
slack status "OOO" --all                # Set status on all workspaces
```

## Token Encryption

Optionally encrypt your tokens with [age](https://github.com/FiloSottile/age) using an SSH key:

```bash
slack config set ssh_key ~/.ssh/id_ed25519
```

Tokens will be stored encrypted in `~/.config/slack-cli/tokens.age`.

## Configuration

Files are stored in XDG-compliant locations:

- **Config**: `~/.config/slack-cli/`
  - `config.json` - Settings
  - `tokens.json` or `tokens.age` - Workspace tokens
  - `presets.json` - Status presets
- **Cache**: `~/.cache/slack-cli/`
  - `users-{workspace}.json` - User cache
  - `channels-{workspace}.json` - Channel cache

## Development

```bash
# Clone the repo
git clone https://github.com/ericboehs/slack-cli.git
cd slack-cli

# Run from source
ruby -Ilib bin/slack --version

# Run tests
rake test

# Build gem
gem build slack-cli.gemspec

# Install locally
gem install ./slack-cli-3.0.0.gem
```

## License

MIT License. See [LICENSE](LICENSE) for details.
