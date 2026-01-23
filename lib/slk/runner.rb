# frozen_string_literal: true

module Slk
  # Dependency injection container providing services to commands
  class Runner
    attr_reader :output, :config, :token_store, :api_client, :cache_store, :preset_store

    # rubocop:disable Metrics/ParameterLists
    def initialize(
      output: nil,
      config: nil,
      token_store: nil,
      api_client: nil,
      cache_store: nil,
      preset_store: nil
    )
      @output = output || Formatters::Output.new
      @config = config || Services::Configuration.new
      @token_store = token_store || Services::TokenStore.new(config: @config)
      @api_client = api_client || Services::ApiClient.new
      @cache_store = cache_store || Services::CacheStore.new
      @preset_store = preset_store || Services::PresetStore.new

      # Wire up warning callbacks to show warnings to users
      wire_up_warnings
    end
    # rubocop:enable Metrics/ParameterLists

    # Workspace helpers
    def workspace(name = nil)
      name ||= @config.primary_workspace
      raise ConfigError, 'No workspace specified and no primary workspace configured' unless name

      @token_store.workspace(name)
    end

    def all_workspaces
      @token_store.all_workspaces
    end

    def workspace_names
      @token_store.workspace_names
    end

    def workspaces?
      !@token_store.empty?
    end

    # API helpers - create API instances bound to workspace
    def users_api(workspace_name = nil)
      Api::Users.new(@api_client, workspace(workspace_name), on_debug: ->(msg) { @output.debug(msg) })
    end

    def conversations_api(workspace_name = nil)
      Api::Conversations.new(@api_client, workspace(workspace_name))
    end

    def dnd_api(workspace_name = nil)
      Api::Dnd.new(@api_client, workspace(workspace_name))
    end

    def client_api(workspace_name = nil)
      Api::Client.new(@api_client, workspace(workspace_name))
    end

    def emoji_api(workspace_name = nil)
      Api::Emoji.new(@api_client, workspace(workspace_name))
    end

    def bots_api(workspace_name = nil)
      Api::Bots.new(@api_client, workspace(workspace_name), on_debug: ->(msg) { @output.debug(msg) })
    end

    def threads_api(workspace_name = nil)
      Api::Threads.new(@api_client, workspace(workspace_name))
    end

    def activity_api(workspace_name = nil)
      Api::Activity.new(@api_client, workspace(workspace_name))
    end

    def search_api(workspace_name = nil)
      Api::Search.new(@api_client, workspace(workspace_name))
    end

    # Formatter helpers
    def message_formatter
      @message_formatter ||= Formatters::MessageFormatter.new(
        output: @output,
        mention_replacer: mention_replacer,
        emoji_replacer: emoji_replacer,
        cache_store: @cache_store,
        api_client: @api_client,
        on_debug: ->(msg) { @output.debug(msg) }
      )
    end

    def mention_replacer
      @mention_replacer ||= Formatters::MentionReplacer.new(
        cache_store: @cache_store,
        api_client: @api_client,
        on_debug: ->(msg) { @output.debug(msg) }
      )
    end

    def emoji_replacer
      @emoji_replacer ||= Formatters::EmojiReplacer.new
    end

    def duration_formatter
      @duration_formatter ||= Formatters::DurationFormatter.new
    end

    def search_formatter
      @search_formatter ||= Formatters::SearchFormatter.new(
        output: @output,
        emoji_replacer: emoji_replacer,
        mention_replacer: mention_replacer
      )
    end

    # Logging
    def log_error(error)
      Support::ErrorLogger.log(error)
    end

    private

    def wire_up_warnings
      warning_handler = ->(message) { @output.warn(message) }

      @config.on_warning = warning_handler
      @token_store.on_warning = warning_handler
      @preset_store.on_warning = warning_handler
      @cache_store.on_warning = warning_handler
    end
  end
end
