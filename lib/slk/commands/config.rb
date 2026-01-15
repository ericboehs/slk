# frozen_string_literal: true

require_relative '../support/help_formatter'

module Slk
  module Commands
    # Manages CLI configuration settings
    class Config < Base
      def execute
        result = validate_options
        return result if result

        dispatch_action
      end

      private

      def dispatch_action
        case positional_args
        in ['show'] | [] then show_config
        in ['setup'] | [_] then run_setup
        in ['get', key] then get_value(key)
        in ['set', key, value] then set_value(key, value)
        end
      end

      protected

      def help_text
        help = Support::HelpFormatter.new('slk config [action]')
        help.description('Manage configuration.')
        add_actions_section(help)
        add_keys_section(help)
        add_options_section(help)
        help.render
      end

      def add_actions_section(help)
        help.section('ACTIONS') do |s|
          s.action('show', 'Show current configuration')
          s.action('setup', 'Run setup wizard')
          s.action('get <key>', 'Get a config value')
          s.action('set <key> <val>', 'Set a config value')
        end
      end

      def add_keys_section(help)
        help.section('CONFIG KEYS') do |s|
          s.item('primary_workspace', 'Default workspace name')
          s.item('ssh_key', 'Path to SSH key for encryption')
          s.item('emoji_dir', 'Custom emoji directory')
        end
      end

      def add_options_section(help)
        help.section('OPTIONS') do |s|
          s.option('-q, --quiet', 'Suppress output')
        end
      end

      private

      def show_config
        display_config_values
        display_workspace_info
        display_paths
        0
      end

      def display_config_values
        puts 'Configuration:'
        puts "  Primary workspace: #{config.primary_workspace || '(not set)'}"
        puts "  SSH key: #{config.ssh_key || '(not set)'}"
        puts "  Emoji dir: #{config.emoji_dir || '(default)'}"
      end

      def display_workspace_info
        puts
        puts "Workspaces: #{runner.workspace_names.join(', ')}"
      end

      def display_paths
        puts
        paths = Support::XdgPaths.new
        puts "Config dir: #{paths.config_dir}"
        puts "Cache dir: #{paths.cache_dir}"
      end

      def run_setup
        wizard = Services::SetupWizard.new(
          runner: runner,
          config: config,
          token_store: token_store,
          output: output
        )
        wizard.run
      end

      def get_value(key)
        value = config[key]
        puts value || '(not set)'

        0
      end

      def set_value(key, value)
        if key == 'ssh_key'
          return 1 if set_ssh_key(value).nil?
        else
          config[key] = value
          success("Set #{key} = #{value}")
        end

        0
      end

      def set_ssh_key(new_path)
        # Expand path and handle unsetting
        new_path = new_path == '' ? nil : File.expand_path(new_path)
        old_path = config.ssh_key

        # Migrate tokens to new encryption setting
        token_store.on_info = ->(msg) { success(msg) }
        token_store.on_warning = ->(msg) { warn(msg) }
        token_store.migrate_encryption(old_path, new_path)

        # Save the new setting
        config['ssh_key'] = new_path
        if new_path
          success("Set ssh_key = #{new_path}")
        else
          success('Cleared ssh_key')
        end
        true # Signal success
      rescue EncryptionError => e
        error(e.message)
        nil # Signal failure
      end
    end
  end
end
