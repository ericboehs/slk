# Changelog

All notable changes to this project will be documented in this file.

## [0.1.0] - 2025-12-14

### Changed
- Complete rewrite from Bash to Ruby
- Now distributed as a Ruby gem (`gem install slk`)
- Command renamed from `slack` to `slk`

### Added
- Pure Ruby implementation (no dependencies)
- Ruby 3.2+ features (Data.define for models)
- Minitest test suite
- Gemspec for gem distribution

### Features
- `slk status` - Get/set/clear status with emoji and duration
- `slk presence` - Get/set presence (away/active)
- `slk dnd` - Manage Do Not Disturb
- `slk messages` - Read channel and DM messages
- `slk unread` - View and clear unread messages
- `slk catchup` - Interactive triage mode
- `slk preset` - Status presets (meeting, lunch, focus, brb, clear)
- `slk workspaces` - Multi-workspace support
- `slk cache` - User/channel cache management
- `slk emoji` - Download workspace custom emoji
- `slk config` - Setup wizard and configuration

### Architecture
- Command pattern with base class
- Dependency injection via Runner
- Immutable value objects (Data.define)
- XDG-compliant config directories
- Optional token encryption with age

## [2.x] - Previous

Bash implementation (see bin/slack.bash for reference).
