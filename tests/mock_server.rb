#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'sinatra', '~> 4.0'
  gem 'rackup', '~> 2.1'
  gem 'webrick', '~> 1.8'
  gem 'json', '~> 2.7'
end

require 'sinatra/base'
require 'json'
require 'fileutils'

# Mock Slack API Server for testing slack-cli
class MockSlackServer < Sinatra::Base
  set :port, ENV.fetch('MOCK_PORT', 8089)
  set :bind, '0.0.0.0'
  set :logging, ENV.fetch('MOCK_DEBUG', 'false') == 'true'
  set :fixtures_dir, File.join(__dir__, 'fixtures')

  # Store scenario overrides per method
  @@scenarios = {}

  helpers do
    def fixture_path(method, scenario = nil)
      scenario ||= @@scenarios[method] || 'default'
      base_dir = settings.fixtures_dir

      # Try scenario-specific file first
      scenario_file = File.join(base_dir, method.gsub('.', '/'), "#{scenario}.json")
      return scenario_file if File.exist?(scenario_file)

      # Fall back to default
      default_file = File.join(base_dir, method.gsub('.', '/'), 'default.json')
      return default_file if File.exist?(default_file)

      # No fixture found
      nil
    end

    def load_fixture(method, scenario = nil)
      path = fixture_path(method, scenario)
      if path && File.exist?(path)
        JSON.parse(File.read(path))
      else
        { 'ok' => false, 'error' => 'fixture_not_found', 'method' => method, 'scenario' => scenario }
      end
    end

    def json_response(data, status_code = 200)
      content_type :json
      status status_code
      data.to_json
    end
  end

  # Health check
  get '/health' do
    json_response({ 'status' => 'ok', 'fixtures_dir' => settings.fixtures_dir })
  end

  # Set scenario for a method (for test setup)
  post '/_test/scenario' do
    data = JSON.parse(request.body.read)
    method = data['method']
    scenario = data['scenario']

    if method && scenario
      @@scenarios[method] = scenario
      json_response({ 'ok' => true, 'method' => method, 'scenario' => scenario })
    else
      json_response({ 'ok' => false, 'error' => 'missing_method_or_scenario' }, 400)
    end
  end

  # Reset all scenarios
  post '/_test/reset' do
    @@scenarios.clear
    json_response({ 'ok' => true, 'message' => 'scenarios_reset' })
  end

  # List available fixtures
  get '/_test/fixtures' do
    fixtures = {}
    Dir.glob(File.join(settings.fixtures_dir, '**/*.json')).each do |file|
      relative = file.sub(settings.fixtures_dir + '/', '')
      parts = relative.split('/')
      scenario = File.basename(parts.pop, '.json')
      method = parts.join('.')
      fixtures[method] ||= []
      fixtures[method] << scenario
    end
    json_response({ 'ok' => true, 'fixtures' => fixtures })
  end

  # Catch-all for Slack API methods
  post '/api/:method' do |method|
    scenario = request.env['HTTP_X_SLACK_SCENARIO']

    if ENV['MOCK_DEBUG'] == 'true'
      puts "[MOCK] #{method} (scenario: #{scenario || @@scenarios[method] || 'default'})"
      puts "[MOCK] Body: #{request.body.read}" if request.body
      request.body.rewind if request.body
    end

    json_response(load_fixture(method, scenario))
  end

  # Handle methods with dots in URL path (e.g., /api/users.profile.get)
  post %r{/api/(.+)} do |method|
    scenario = request.env['HTTP_X_SLACK_SCENARIO']

    if ENV['MOCK_DEBUG'] == 'true'
      puts "[MOCK] #{method} (scenario: #{scenario || @@scenarios[method] || 'default'})"
    end

    json_response(load_fixture(method, scenario))
  end

  # Support GET for some endpoints (like conversations.history with query params)
  get %r{/api/(.+)} do |method|
    # Strip query params from method name
    method = method.split('?').first
    scenario = request.env['HTTP_X_SLACK_SCENARIO']

    if ENV['MOCK_DEBUG'] == 'true'
      puts "[MOCK GET] #{method} (scenario: #{scenario || @@scenarios[method] || 'default'})"
    end

    json_response(load_fixture(method, scenario))
  end
end

if __FILE__ == $0
  puts "Starting Mock Slack Server on port #{ENV.fetch('MOCK_PORT', 8089)}..."
  puts "Fixtures directory: #{File.join(__dir__, 'fixtures')}"
  puts "Debug mode: #{ENV.fetch('MOCK_DEBUG', 'false')}"
  puts
  puts "Test endpoints:"
  puts "  POST /_test/scenario  - Set scenario for a method"
  puts "  POST /_test/reset     - Reset all scenarios"
  puts "  GET  /_test/fixtures  - List available fixtures"
  puts "  GET  /health          - Health check"
  puts
  MockSlackServer.run!
end
