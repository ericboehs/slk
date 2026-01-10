# frozen_string_literal: true

module SlackCli
  class Runner
    attr_reader :output, :config, :token_store, :api_client, :cache_store, :preset_store

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

    # Workspace helpers
    def workspace(name = nil)
      name ||= @config.primary_workspace
      raise ConfigError, "No workspace specified and no primary workspace configured" unless name

      @token_store.workspace(name)
    end

    def all_workspaces
      @token_store.all_workspaces
    end

    def workspace_names
      @token_store.workspace_names
    end

    def has_workspaces?
      !@token_store.empty?
    end

    # API helpers - create API instances bound to workspace
    def users_api(ws = nil)
      Api::Users.new(@api_client, workspace(ws))
    end

    def conversations_api(ws = nil)
      Api::Conversations.new(@api_client, workspace(ws))
    end

    def dnd_api(ws = nil)
      Api::Dnd.new(@api_client, workspace(ws))
    end

    def client_api(ws = nil)
      Api::Client.new(@api_client, workspace(ws))
    end

    def emoji_api(ws = nil)
      Api::Emoji.new(@api_client, workspace(ws))
    end

    def bots_api(ws = nil)
      Api::Bots.new(@api_client, workspace(ws))
    end

    def threads_api(ws = nil)
      Api::Threads.new(@api_client, workspace(ws))
    end

    # Formatter helpers
    def message_formatter
      @message_formatter ||= Formatters::MessageFormatter.new(
        output: @output,
        mention_replacer: mention_replacer,
        emoji_replacer: emoji_replacer,
        cache_store: @cache_store,
        api_client: @api_client
      )
    end

    def mention_replacer
      @mention_replacer ||= Formatters::MentionReplacer.new(
        cache_store: @cache_store,
        api_client: @api_client
      )
    end

    def emoji_replacer
      @emoji_replacer ||= Formatters::EmojiReplacer.new
    end

    def duration_formatter
      @duration_formatter ||= Formatters::DurationFormatter.new
    end

    # Logging
    def log_error(error)
      paths = Support::XdgPaths.new
      paths.ensure_cache_dir

      log_file = paths.cache_file("error.log")
      File.open(log_file, "a") do |f|
        f.puts "#{Time.now.iso8601} - #{error.class}: #{error.message}"
        f.puts error.backtrace.first(10).map { |line| "  #{line}" }.join("\n") if error.backtrace
        f.puts
      end
    end

    private

    def wire_up_warnings
      warning_handler = ->(message) { @output.warn(message) }

      @config.on_warning = warning_handler
      @token_store.on_warning = warning_handler
      @preset_store.on_warning = warning_handler
    end
  end
end
