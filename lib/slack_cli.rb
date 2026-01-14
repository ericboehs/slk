# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'fileutils'
require 'optparse'
require 'time'
require 'io/console'

# Slack CLI - A command-line interface for Slack
module SlackCli
  class Error < StandardError; end
  class ApiError < Error; end
  class ConfigError < Error; end
  class EncryptionError < Error; end
  class TokenStoreError < Error; end
  class WorkspaceNotFoundError < ConfigError; end
  class PresetNotFoundError < ConfigError; end

  autoload :VERSION, 'slack_cli/version'
  autoload :CLI, 'slack_cli/cli'
  autoload :Runner, 'slack_cli/runner'

  # Data models for Slack entities
  module Models
    autoload :Duration, 'slack_cli/models/duration'
    autoload :Workspace, 'slack_cli/models/workspace'
    autoload :Status, 'slack_cli/models/status'
    autoload :Message, 'slack_cli/models/message'
    autoload :Reaction, 'slack_cli/models/reaction'
    autoload :User, 'slack_cli/models/user'
    autoload :Channel, 'slack_cli/models/channel'
    autoload :Preset, 'slack_cli/models/preset'
  end

  # Application services for configuration, caching, and API communication
  module Services
    autoload :ApiClient, 'slack_cli/services/api_client'
    autoload :Configuration, 'slack_cli/services/configuration'
    autoload :TokenStore, 'slack_cli/services/token_store'
    autoload :CacheStore, 'slack_cli/services/cache_store'
    autoload :PresetStore, 'slack_cli/services/preset_store'
    autoload :Encryption, 'slack_cli/services/encryption'
    autoload :ReactionEnricher, 'slack_cli/services/reaction_enricher'
  end

  # Output formatters for messages, durations, and emoji
  module Formatters
    autoload :Output, 'slack_cli/formatters/output'
    autoload :DurationFormatter, 'slack_cli/formatters/duration_formatter'
    autoload :MentionReplacer, 'slack_cli/formatters/mention_replacer'
    autoload :EmojiReplacer, 'slack_cli/formatters/emoji_replacer'
    autoload :MessageFormatter, 'slack_cli/formatters/message_formatter'
  end

  # CLI commands implementing user-facing functionality
  module Commands
    autoload :Base, 'slack_cli/commands/base'
    autoload :Status, 'slack_cli/commands/status'
    autoload :Presence, 'slack_cli/commands/presence'
    autoload :Dnd, 'slack_cli/commands/dnd'
    autoload :Messages, 'slack_cli/commands/messages'
    autoload :Thread, 'slack_cli/commands/thread'
    autoload :Unread, 'slack_cli/commands/unread'
    autoload :Catchup, 'slack_cli/commands/catchup'
    autoload :Activity, 'slack_cli/commands/activity'
    autoload :Preset, 'slack_cli/commands/preset'
    autoload :Workspaces, 'slack_cli/commands/workspaces'
    autoload :Cache, 'slack_cli/commands/cache'
    autoload :Emoji, 'slack_cli/commands/emoji'
    autoload :Config, 'slack_cli/commands/config'
    autoload :Help, 'slack_cli/commands/help'
  end

  # Thin wrappers around Slack API endpoints
  module Api
    autoload :Users, 'slack_cli/api/users'
    autoload :Conversations, 'slack_cli/api/conversations'
    autoload :Dnd, 'slack_cli/api/dnd'
    autoload :Emoji, 'slack_cli/api/emoji'
    autoload :Client, 'slack_cli/api/client'
    autoload :Bots, 'slack_cli/api/bots'
    autoload :Threads, 'slack_cli/api/threads'
    autoload :Usergroups, 'slack_cli/api/usergroups'
    autoload :Activity, 'slack_cli/api/activity'
  end

  # Utility classes for paths, parsing, and helpers
  module Support
    autoload :XdgPaths, 'slack_cli/support/xdg_paths'
    autoload :SlackUrlParser, 'slack_cli/support/slack_url_parser'
    autoload :InlineImages, 'slack_cli/support/inline_images'
    autoload :HelpFormatter, 'slack_cli/support/help_formatter'
    autoload :ErrorLogger, 'slack_cli/support/error_logger'
    autoload :UserResolver, 'slack_cli/support/user_resolver'
  end
end
