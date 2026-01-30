# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'fileutils'
require 'optparse'
require 'time'
require 'io/console'

# Slack CLI - A command-line interface for Slack
module Slk
  class Error < StandardError; end
  class ApiError < Error; end
  class ConfigError < Error; end
  class EncryptionError < Error; end
  class TokenStoreError < Error; end
  class WorkspaceNotFoundError < ConfigError; end
  class PresetNotFoundError < ConfigError; end

  autoload :VERSION, 'slk/version'
  autoload :CLI, 'slk/cli'
  autoload :Runner, 'slk/runner'

  # Data models for Slack entities
  module Models
    autoload :Duration, 'slk/models/duration'
    autoload :Workspace, 'slk/models/workspace'
    autoload :Status, 'slk/models/status'
    autoload :Message, 'slk/models/message'
    autoload :Reaction, 'slk/models/reaction'
    autoload :User, 'slk/models/user'
    autoload :Channel, 'slk/models/channel'
    autoload :Preset, 'slk/models/preset'
    autoload :SearchResult, 'slk/models/search_result'
  end

  # Application services for configuration, caching, and API communication
  module Services
    autoload :ApiClient, 'slk/services/api_client'
    autoload :Configuration, 'slk/services/configuration'
    autoload :TokenStore, 'slk/services/token_store'
    autoload :TokenLoader, 'slk/services/token_loader'
    autoload :TokenSaver, 'slk/services/token_saver'
    autoload :CacheStore, 'slk/services/cache_store'
    autoload :PresetStore, 'slk/services/preset_store'
    autoload :Encryption, 'slk/services/encryption'
    autoload :ReactionEnricher, 'slk/services/reaction_enricher'
    autoload :GemojiSync, 'slk/services/gemoji_sync'
    autoload :EmojiDownloader, 'slk/services/emoji_downloader'
    autoload :EmojiSearcher, 'slk/services/emoji_searcher'
    autoload :ActivityEnricher, 'slk/services/activity_enricher'
    autoload :UnreadMarker, 'slk/services/unread_marker'
    autoload :TargetResolver, 'slk/services/target_resolver'
    autoload :SetupWizard, 'slk/services/setup_wizard'
    autoload :UserLookup, 'slk/services/user_lookup'
  end

  # Output formatters for messages, durations, and emoji
  module Formatters
    autoload :Output, 'slk/formatters/output'
    autoload :DurationFormatter, 'slk/formatters/duration_formatter'
    autoload :MentionReplacer, 'slk/formatters/mention_replacer'
    autoload :EmojiReplacer, 'slk/formatters/emoji_replacer'
    autoload :MessageFormatter, 'slk/formatters/message_formatter'
    autoload :ReactionFormatter, 'slk/formatters/reaction_formatter'
    autoload :JsonMessageFormatter, 'slk/formatters/json_message_formatter'
    autoload :ActivityFormatter, 'slk/formatters/activity_formatter'
    autoload :AttachmentFormatter, 'slk/formatters/attachment_formatter'
    autoload :BlockFormatter, 'slk/formatters/block_formatter'
    autoload :SearchFormatter, 'slk/formatters/search_formatter'
  end

  # CLI commands implementing user-facing functionality
  module Commands
    autoload :Base, 'slk/commands/base'
    autoload :Status, 'slk/commands/status'
    autoload :Presence, 'slk/commands/presence'
    autoload :Dnd, 'slk/commands/dnd'
    autoload :Messages, 'slk/commands/messages'
    autoload :Thread, 'slk/commands/thread'
    autoload :Unread, 'slk/commands/unread'
    autoload :Catchup, 'slk/commands/catchup'
    autoload :Activity, 'slk/commands/activity'
    autoload :Search, 'slk/commands/search'
    autoload :Preset, 'slk/commands/preset'
    autoload :Workspaces, 'slk/commands/workspaces'
    autoload :Cache, 'slk/commands/cache'
    autoload :Emoji, 'slk/commands/emoji'
    autoload :Config, 'slk/commands/config'
    autoload :Help, 'slk/commands/help'
  end

  # Thin wrappers around Slack API endpoints
  module Api
    autoload :Users, 'slk/api/users'
    autoload :Conversations, 'slk/api/conversations'
    autoload :Dnd, 'slk/api/dnd'
    autoload :Emoji, 'slk/api/emoji'
    autoload :Client, 'slk/api/client'
    autoload :Bots, 'slk/api/bots'
    autoload :Threads, 'slk/api/threads'
    autoload :Usergroups, 'slk/api/usergroups'
    autoload :Activity, 'slk/api/activity'
    autoload :Search, 'slk/api/search'
  end

  # Utility classes for paths, parsing, and helpers
  module Support
    autoload :XdgPaths, 'slk/support/xdg_paths'
    autoload :SlackUrlParser, 'slk/support/slack_url_parser'
    autoload :InlineImages, 'slk/support/inline_images'
    autoload :HelpFormatter, 'slk/support/help_formatter'
    autoload :ErrorLogger, 'slk/support/error_logger'
    autoload :UserResolver, 'slk/support/user_resolver'
    autoload :TextWrapper, 'slk/support/text_wrapper'
    autoload :InteractivePrompt, 'slk/support/interactive_prompt'
    autoload :DateParser, 'slk/support/date_parser'
  end
end
