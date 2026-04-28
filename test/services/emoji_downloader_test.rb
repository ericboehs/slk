# frozen_string_literal: true

require 'test_helper'

class EmojiDownloaderTest < Minitest::Test
  def test_download_writes_files_for_non_aliases
    Dir.mktmpdir do |dir|
      downloader = Slk::Services::EmojiDownloader.new(emoji_dir: dir)
      emoji_map = { 'foo' => 'https://e.com/foo.png' }

      stats = with_stub_http(mock_success('PNGDATA')) do
        downloader.download('ws', emoji_map)
      end

      assert_equal 1, stats[:downloaded]
      assert_equal 0, stats[:aliases]
      assert File.exist?(File.join(dir, 'ws', 'foo.png'))
    end
  end

  def test_download_counts_aliases
    Dir.mktmpdir do |dir|
      downloader = Slk::Services::EmojiDownloader.new(emoji_dir: dir)
      emoji_map = { 'a' => 'alias:other', 'b' => 'https://e.com/b.png' }

      stats = with_stub_http(mock_success('X')) { downloader.download('ws', emoji_map) }

      assert_equal 1, stats[:aliases]
      assert_equal 1, stats[:downloaded]
    end
  end

  def test_download_skips_existing_files
    Dir.mktmpdir do |dir|
      ws_dir = File.join(dir, 'ws')
      FileUtils.mkdir_p(ws_dir)
      File.write(File.join(ws_dir, 'foo.png'), 'CACHED')

      downloader = Slk::Services::EmojiDownloader.new(emoji_dir: dir)
      stats = with_stub_http(mock_success('NEW')) do
        downloader.download('ws', { 'foo' => 'https://e.com/foo.png' })
      end

      assert_equal 1, stats[:skipped]
      assert_equal 'CACHED', File.read(File.join(ws_dir, 'foo.png'))
    end
  end

  def test_download_uses_png_when_no_extension
    Dir.mktmpdir do |dir|
      downloader = Slk::Services::EmojiDownloader.new(emoji_dir: dir)

      with_stub_http(mock_success('X')) do
        downloader.download('ws', { 'noext' => 'https://e.com/noext' })
      end

      assert File.exist?(File.join(dir, 'ws', 'noext.png'))
    end
  end

  def test_download_handles_http_failure
    Dir.mktmpdir do |dir|
      downloader = Slk::Services::EmojiDownloader.new(emoji_dir: dir)

      stats = with_stub_http(mock_failure(500)) do
        downloader.download('ws', { 'foo' => 'https://e.com/foo.png' })
      end

      assert_equal 1, stats[:failed]
    end
  end

  def test_download_handles_network_error_with_debug
    Dir.mktmpdir do |dir|
      msgs = []
      downloader = Slk::Services::EmojiDownloader.new(emoji_dir: dir, on_debug: ->(m) { msgs << m })

      stats = with_stub_http_error(SocketError) do
        downloader.download('ws', { 'foo' => 'https://e.com/foo.png' })
      end

      assert_equal 1, stats[:failed]
      assert(msgs.any? { |m| m.include?('Failed to download') })
    end
  end

  def test_download_handles_invalid_uri
    Dir.mktmpdir do |dir|
      downloader = Slk::Services::EmojiDownloader.new(emoji_dir: dir)

      stats = with_stub_http(mock_success('X')) do
        downloader.download('ws', { 'foo' => 'http://[bad uri' })
      end

      assert_equal 1, stats[:failed]
    end
  end

  def test_update_stats_ignores_unknown_result
    Dir.mktmpdir do |dir|
      downloader = Slk::Services::EmojiDownloader.new(emoji_dir: dir)
      stats = { downloaded: 0, skipped: 0, failed: 0, aliases: 0, total: 0 }
      downloader.send(:update_stats, stats, :unknown)
      assert_equal 0, stats[:downloaded]
    end
  end

  def test_download_handles_network_error_without_on_debug
    Dir.mktmpdir do |dir|
      downloader = Slk::Services::EmojiDownloader.new(emoji_dir: dir)
      stats = with_stub_http_error(SocketError) do
        downloader.download('ws', { 'foo' => 'https://e.com/foo.png' })
      end
      assert_equal 1, stats[:failed]
    end
  end

  def test_download_calls_progress_callback
    Dir.mktmpdir do |dir|
      progress = []
      downloader = Slk::Services::EmojiDownloader.new(
        emoji_dir: dir, on_progress: ->(*args) { progress << args }
      )

      with_stub_http(mock_success('X')) do
        downloader.download('ws', { 'foo' => 'https://e.com/foo.png' })
      end

      refute_empty progress
    end
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
