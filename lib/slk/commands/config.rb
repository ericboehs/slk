# frozen_string_literal: true

require_relative 'ssh_key_manager'

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
        in ['unset', key] then unset_value(key)
        end
      end

      protected

      def help_text
        Support::HelpFormatter.new('slk config [action]').tap do |h|
          h.description('Manage configuration.')
          h.section('ACTIONS') { |s| add_actions(s) }
          h.section('CONFIG KEYS') { |s| add_keys(s) }
          h.section('OPTIONS') { |s| s.option('-q, --quiet', 'Suppress output') }
        end.render
      end

      def add_actions(section)
        section.action('show', 'Show current configuration')
        section.action('setup', 'Run setup wizard')
        section.action('get <key>', 'Get a config value')
        section.action('set <key> <val>', 'Set a config value')
        section.action('unset <key>', 'Remove a config value')
      end

      def add_keys(section)
        section.item('primary_workspace', 'Default workspace name')
        section.item('ssh_key', 'Path to SSH key for encryption')
        section.item('emoji_dir', 'Custom emoji directory')
      end

      private

      def show_config
        print_config_values
        print_paths
        0
      end

      def print_config_values
        puts 'Configuration:'
        puts "  Primary workspace: #{config.primary_workspace || '(not set)'}"
        puts "  SSH key: #{config.ssh_key || '(not set)'}"
        puts "  Emoji dir: #{config.emoji_dir || '(default)'}"
        puts
        puts "Workspaces: #{runner.workspace_names.join(', ')}"
      end

      def print_paths
        paths = Support::XdgPaths.new
        puts
        puts "Config dir: #{paths.config_dir}"
        puts "Cache dir: #{paths.cache_dir}"
      end

      def run_setup
        Services::SetupWizard.new(runner: runner, config: config, token_store: token_store, output: output).run
      end

      def get_value(key)
        puts config[key] || '(not set)'
        0
      end

      def set_value(key, value)
        return handle_ssh_key_result(ssh_key_manager.set(value)) if key == 'ssh_key'

        config[key] = value
        success("Set #{key} = #{value}")
        0
      end

      def unset_value(key)
        return handle_ssh_key_result(ssh_key_manager.unset) if key == 'ssh_key'

        config[key] = nil
        success("Unset #{key}")
        0
      end

      def ssh_key_manager
        @ssh_key_manager ||= SshKeyManager.new(config: config, token_store: token_store, output: output).tap do |mgr|
          mgr.on_info = ->(msg) { success(msg) }
          mgr.on_warning = ->(msg) { warn(msg) }
        end
      end

      def handle_ssh_key_result(result)
        return success(result[:message]) || 0 if result[:success]

        error(result[:error])
        1
      end
    end
  end
end
