# frozen_string_literal: true

if ENV['COVERAGE']
  require 'simplecov'
  SimpleCov.start do
    add_filter '/test/'
    enable_coverage :branch
    minimum_coverage line: 95, branch: 95
  end
end

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'minitest/autorun'
require 'minitest/mock'
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
        old_appdata = ENV.fetch('APPDATA', nil)
        old_localappdata = ENV.fetch('LOCALAPPDATA', nil)

        ENV['XDG_CONFIG_HOME'] = dir
        ENV['XDG_CACHE_HOME'] = "#{dir}/cache"
        # Also set Windows env vars for cross-platform compatibility
        ENV['APPDATA'] = dir
        ENV['LOCALAPPDATA'] = "#{dir}/cache"

        yield dir
      ensure
        ENV['XDG_CONFIG_HOME'] = old_config
        ENV['XDG_CACHE_HOME'] = old_cache
        ENV['APPDATA'] = old_appdata
        ENV['LOCALAPPDATA'] = old_localappdata
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
        response = @responses[method] || { 'ok' => true }
        # Stubbing an exception simulates the call failing rather than
        # returning an error payload — a network drop, a rate limit.
        raise response if response.is_a?(Exception)

        response
      end

      def get(workspace, method, params = {})
        @calls << { workspace: workspace.name, method: method, params: params }
        @responses[method] || { 'ok' => true }
      end

      def post_form(workspace, method, params = {})
        post(workspace, method, params)
      end

      def call_count
        @calls.size
      end
    end

    # Run a block with TZ set, for assertions that only mean anything in a
    # specific zone (DST transitions).
    #
    # Ruby on Windows reads POSIX-form TZ, not IANA names, so the assignment
    # can be silently ignored — leaving the test asserting against whatever
    # zone the machine happens to be in. Verify the switch took effect and skip
    # if it did not, rather than fail somewhere confusing.
    def with_timezone(zone, expected_offset:)
      original = ENV.fetch('TZ', nil)
      ENV['TZ'] = zone
      skip "TZ=#{zone} is not honoured on this platform" unless Time.new(2026, 1, 1).utc_offset == expected_offset

      yield
    ensure
      ENV['TZ'] = original
    end

    # America/Chicago in January: CST, six hours behind UTC.
    CHICAGO_WINTER_OFFSET = -6 * 3600

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
