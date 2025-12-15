# Changelog

All notable changes to this project will be documented in this file.

## [3.0.0] - 2025-12-14

### Changed
- Complete rewrite from Bash to Ruby
- Now distributed as a Ruby gem

### Added
- Pure Ruby implementation (no dependencies)
- Ruby 3.2+ features (Data.define for models)
- Minitest test suite
- Gemspec for gem distribution

### Features
- `slack status` - Get/set/clear status with emoji and duration
- `slack presence` - Get/set presence (away/active)
- `slack dnd` - Manage Do Not Disturb
- `slack messages` - Read channel and DM messages
- `slack unread` - View and clear unread messages
- `slack catchup` - Interactive triage mode
- `slack preset` - Status presets (meeting, lunch, focus, brb, clear)
- `slack workspaces` - Multi-workspace support
- `slack cache` - User/channel cache management
- `slack emoji` - Download workspace custom emoji
- `slack config` - Setup wizard and configuration

### Architecture
- Command pattern with base class
- Dependency injection via Runner
- Immutable value objects (Data.define)
- XDG-compliant config directories
- Optional token encryption with age

## [2.x] - Previous

Bash implementation (see bin/slack.bash for reference).
