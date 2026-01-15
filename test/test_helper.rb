# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'minitest/autorun'
require 'slk'
require 'stringio'
require 'tmpdir'
require 'json'

module Slk
  module TestHelpers
    # Create a test output that captures to StringIO
    def test_output(color: false)
      io = StringIO.new
      err = StringIO.new
      Formatters::Output.new(io: io, err: err, color: color)
    end

    # Create a runner with test dependencies
    def test_runner(output: nil, config: nil, api_client: nil)
      Runner.new(
        output: output || test_output,
        config: config,
        api_client: api_client
      )
    end

    # Create a temporary config directory
    def with_temp_config
      Dir.mktmpdir('slk-test') do |dir|
        old_config = ENV.fetch('XDG_CONFIG_HOME', nil)
        old_cache = ENV.fetch('XDG_CACHE_HOME', nil)
        ENV['XDG_CONFIG_HOME'] = dir
        ENV['XDG_CACHE_HOME'] = "#{dir}/cache"

        yield dir
      ensure
        ENV['XDG_CONFIG_HOME'] = old_config
        ENV['XDG_CACHE_HOME'] = old_cache
      end
    end

    # Load fixture JSON
    def fixture(path)
      file = File.join(File.dirname(__FILE__), 'fixtures', path)
      JSON.parse(File.read(file))
    end

    # Mock API client that returns fixture data
    class MockApiClient
      attr_reader :calls

      def initialize
        @calls = []
        @responses = {}
      end

      def stub(method, response)
        @responses[method] = response
      end

      def post(workspace, method, params = {})
        @calls << { workspace: workspace.name, method: method, params: params }
        @responses[method] || { 'ok' => true }
      end

      def get(workspace, method, params = {})
        @calls << { workspace: workspace.name, method: method, params: params }
        @responses[method] || { 'ok' => true }
      end

      def post_form(workspace, method, params = {})
        post(workspace, method, params)
      end
    end

    # Mock workspace
    def mock_workspace(name = 'test', token = 'xoxb-test-token')
      Models::Workspace.new(name: name, token: token)
    end
  end
end

module Minitest
  class Test
    include Slk::TestHelpers
  end
end
