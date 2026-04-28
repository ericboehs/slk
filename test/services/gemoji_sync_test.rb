# frozen_string_literal: true

require 'test_helper'

class GemojiSyncTest < Minitest::Test
  def test_sync_writes_emoji_file_on_success
    Dir.mktmpdir do |dir|
      sync = Slk::Services::GemojiSync.new(cache_dir: dir)
      data = [{ 'emoji' => "\u{1F600}", 'aliases' => %w[grinning smile_face] }]

      result = with_stub_http(mock_success(JSON.generate(data))) { sync.sync }

      assert result[:success]
      assert_equal 2, result[:count]
      assert File.exist?(File.join(dir, 'gemoji.json'))
      written = JSON.parse(File.read(File.join(dir, 'gemoji.json')))
      assert_equal "\u{1F600}", written['grinning']
    end
  end

  def test_sync_calls_on_progress_callback
    Dir.mktmpdir do |dir|
      messages = []
      sync = Slk::Services::GemojiSync.new(cache_dir: dir, on_progress: ->(m) { messages << m })

      with_stub_http(mock_success('[]')) { sync.sync }

      assert(messages.any? { |m| m.include?('Downloading') })
    end
  end

  def test_sync_returns_error_on_http_failure
    Dir.mktmpdir do |dir|
      sync = Slk::Services::GemojiSync.new(cache_dir: dir)
      result = with_stub_http(mock_failure(500)) { sync.sync }

      assert_match(/Failed to download/, result[:error])
    end
  end

  def test_sync_returns_error_on_network_error
    Dir.mktmpdir do |dir|
      sync = Slk::Services::GemojiSync.new(cache_dir: dir)
      result = with_stub_http_error(SocketError) { sync.sync }

      assert_match(/Network error/, result[:error])
    end
  end

  def test_sync_returns_error_on_invalid_json
    Dir.mktmpdir do |dir|
      sync = Slk::Services::GemojiSync.new(cache_dir: dir)
      result = with_stub_http(mock_success('not json{')) { sync.sync }

      assert_match(/Failed to parse emoji data/, result[:error])
    end
  end

  def test_sync_skips_emoji_without_char
    Dir.mktmpdir do |dir|
      sync = Slk::Services::GemojiSync.new(cache_dir: dir)
      data = [{ 'aliases' => %w[no_char] }, { 'emoji' => 'X', 'aliases' => %w[x] }]

      result = with_stub_http(mock_success(JSON.generate(data))) { sync.sync }
      assert_equal 1, result[:count]
    end
  end

  def test_sync_skips_emoji_without_aliases
    Dir.mktmpdir do |dir|
      sync = Slk::Services::GemojiSync.new(cache_dir: dir)
      data = [{ 'emoji' => 'X' }]
      result = with_stub_http(mock_success(JSON.generate(data))) { sync.sync }
      assert_equal 0, result[:count]
    end
  end

  def test_sync_returns_error_on_save_failure
    Dir.mktmpdir do |dir|
      bad_dir = File.join(dir, 'cache')
      sync = Slk::Services::GemojiSync.new(cache_dir: bad_dir)
      data = [{ 'emoji' => 'X', 'aliases' => %w[x] }]

      File.stub(:write, ->(*_args) { raise Errno::ENOSPC, 'no space' }) do
        result = with_stub_http(mock_success(JSON.generate(data))) { sync.sync }
        assert_match(/File system error/, result[:error])
      end
    end
  end

  def test_emoji_json_path_returns_full_path
    sync = Slk::Services::GemojiSync.new(cache_dir: '/tmp/x')
    assert_equal '/tmp/x/gemoji.json', sync.emoji_json_path
  end

  private

  def mock_success(body)
    response = Net::HTTPOK.allocate
    response.instance_variable_set(:@body, body)
    response.instance_variable_set(:@read, true)
    response
  end

  def mock_failure(code)
    klass = Net::HTTPResponse::CODE_TO_OBJ[code.to_s] || Net::HTTPServerError
    response = klass.allocate
    response.instance_variable_set(:@body, '')
    response.instance_variable_set(:@read, true)
    response.define_singleton_method(:code) { code.to_s }
    response
  end

  def with_stub_http(response)
    original_new = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) do |*_args|
      StubHTTP.new(->(_req) { response })
    end
    yield
  ensure
    Net::HTTP.define_singleton_method(:new, original_new)
  end

  def with_stub_http_error(error_class)
    original_new = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) do |*_args|
      StubHTTP.new(->(_req) { raise error_class })
    end
    yield
  ensure
    Net::HTTP.define_singleton_method(:new, original_new)
  end

  class StubHTTP
    attr_writer :use_ssl, :verify_mode, :open_timeout, :read_timeout, :cert_store

    def initialize(handler)
      @handler = handler
    end

    def cert_store
      @cert_store ||= Object.new.tap { |o| o.define_singleton_method(:set_default_paths) { nil } }
    end

    def request(req) = @handler.call(req)
  end
end
