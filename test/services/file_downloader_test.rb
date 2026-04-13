# frozen_string_literal: true

require 'test_helper'

class FileDownloaderTest < Minitest::Test
  def test_downloads_file_and_returns_path
    with_temp_config do |dir|
      downloader = build_downloader(dir)
      workspace = mock_workspace
      message = build_message(files: [
                                { 'id' => 'F123', 'name' => 'image.png', 'url_private_download' => 'https://files.slack.com/download/image.png' }
                              ])

      with_stub_http(mock_success('PNG_DATA')) do
        paths = downloader.download_message_files([message], workspace)

        assert_equal 1, paths.size
        assert paths.key?('F123')
        assert_equal 'PNG_DATA', File.read(paths['F123'])
        assert paths['F123'].end_with?('F123_image.png')
      end
    end
  end

  def test_skips_cached_file
    with_temp_config do |dir|
      files_dir = File.join(dir, 'cache', 'slk', 'files', 'test')
      FileUtils.mkdir_p(files_dir)
      cached_path = File.join(files_dir, 'F123_image.png')
      File.write(cached_path, 'CACHED')

      downloader = build_downloader(dir)
      workspace = mock_workspace
      message = build_message(files: [
                                { 'id' => 'F123', 'name' => 'image.png', 'url_private_download' => 'https://files.slack.com/download/image.png' }
                              ])

      paths = downloader.download_message_files([message], workspace)

      assert_equal cached_path, paths['F123']
      assert_equal 'CACHED', File.read(paths['F123'])
    end
  end

  def test_skips_file_without_id
    with_temp_config do |dir|
      downloader = build_downloader(dir)
      workspace = mock_workspace
      message = build_message(files: [
                                { 'name' => 'image.png', 'url_private_download' => 'https://files.slack.com/download/image.png' }
                              ])

      paths = downloader.download_message_files([message], workspace)

      assert_empty paths
    end
  end

  def test_skips_file_without_download_url
    with_temp_config do |dir|
      downloader = build_downloader(dir)
      workspace = mock_workspace
      message = build_message(files: [{ 'id' => 'F123', 'name' => 'image.png' }])

      paths = downloader.download_message_files([message], workspace)

      assert_empty paths
    end
  end

  def test_returns_empty_on_http_failure
    with_temp_config do |dir|
      downloader = build_downloader(dir)
      workspace = mock_workspace
      message = build_message(files: [
                                { 'id' => 'F123', 'name' => 'secret.png', 'url_private_download' => 'https://files.slack.com/download/secret.png' }
                              ])

      with_stub_http(mock_failure(401)) do
        paths = downloader.download_message_files([message], workspace)

        assert_empty paths
      end
    end
  end

  def test_downloads_attachment_image
    with_temp_config do |dir|
      downloader = build_downloader(dir)
      workspace = mock_workspace
      message = build_message(attachments: [{ 'image_url' => 'https://cdn.example.com/image.jpg' }])

      with_stub_http(mock_success('JPG_DATA')) do
        paths = downloader.download_message_files([message], workspace)

        key = 'att_1234567890.123456_0'
        assert paths.key?(key)
        assert_equal 'JPG_DATA', File.read(paths[key])
      end
    end
  end

  def test_skips_non_image_attachment_url
    with_temp_config do |dir|
      downloader = build_downloader(dir)
      workspace = mock_workspace
      message = build_message(attachments: [{ 'image_url' => 'https://cdn.example.com/document.pdf' }])

      paths = downloader.download_message_files([message], workspace)

      assert_empty paths
    end
  end

  def test_allows_giphy_urls
    with_temp_config do |dir|
      downloader = build_downloader(dir)
      workspace = mock_workspace
      message = build_message(attachments: [{ 'image_url' => 'https://media.giphy.com/giphy/media.gif' }])

      with_stub_http(mock_success('GIF_DATA')) do
        paths = downloader.download_message_files([message], workspace)

        assert_equal 1, paths.size
      end
    end
  end

  def test_allows_tenor_urls
    with_temp_config do |dir|
      downloader = build_downloader(dir)
      workspace = mock_workspace
      message = build_message(attachments: [{ 'image_url' => 'https://tenor.com/view/funny.gif' }])

      with_stub_http(mock_success('GIF_DATA')) do
        paths = downloader.download_message_files([message], workspace)

        assert_equal 1, paths.size
      end
    end
  end

  def test_follows_single_redirect
    with_temp_config do |dir|
      downloader = build_downloader(dir)
      workspace = mock_workspace
      message = build_message(attachments: [{ 'image_url' => 'https://cdn.example.com/redir.png' }])

      with_stub_http_sequence([
                                mock_redirect('https://cdn.example.com/final.png'),
                                mock_success('FINAL_DATA')
                              ]) do
        paths = downloader.download_message_files([message], workspace)

        assert_equal 1, paths.size
        assert_equal 'FINAL_DATA', File.read(paths.values.first)
      end
    end
  end

  def test_follows_chained_redirects
    with_temp_config do |dir|
      downloader = build_downloader(dir)
      workspace = mock_workspace
      message = build_message(attachments: [{ 'image_url' => 'https://cdn.example.com/hop1.png' }])

      with_stub_http_sequence([
                                mock_redirect('https://cdn.example.com/hop2.png'),
                                mock_redirect('https://cdn.example.com/final.png'),
                                mock_success('CHAINED_DATA')
                              ]) do
        paths = downloader.download_message_files([message], workspace)

        assert_equal 1, paths.size
        assert_equal 'CHAINED_DATA', File.read(paths.values.first)
      end
    end
  end

  def test_handles_relative_redirect
    with_temp_config do |dir|
      downloader = build_downloader(dir)
      workspace = mock_workspace
      message = build_message(attachments: [{ 'image_url' => 'https://cdn.example.com/redir.png' }])

      with_stub_http_sequence([
                                mock_redirect('/actual.png'),
                                mock_success('RELATIVE_DATA')
                              ]) do
        paths = downloader.download_message_files([message], workspace)

        assert_equal 1, paths.size
        assert_equal 'RELATIVE_DATA', File.read(paths.values.first)
      end
    end
  end

  def test_sanitizes_filename_with_special_characters
    with_temp_config do |dir|
      downloader = build_downloader(dir)
      workspace = mock_workspace
      message = build_message(files: [
                                { 'id' => 'F999', 'name' => 'my/file:name?.png', 'url_private_download' => 'https://files.slack.com/f.png' }
                              ])

      with_stub_http(mock_success('DATA')) do
        paths = downloader.download_message_files([message], workspace)

        assert paths.key?('F999')
        assert_match(/F999_my_file_name_.png/, paths['F999'])
      end
    end
  end

  def test_calls_on_debug_for_downloads
    debug_messages = []

    with_temp_config do |dir|
      downloader = Slk::Services::FileDownloader.new(
        cache_dir: File.join(dir, 'cache', 'slk'),
        on_debug: ->(msg) { debug_messages << msg }
      )
      workspace = mock_workspace
      message = build_message(files: [
                                { 'id' => 'F123', 'name' => 'test.png', 'url_private_download' => 'https://files.slack.com/test.png' }
                              ])

      with_stub_http(mock_success('DATA')) do
        downloader.download_message_files([message], workspace)
      end
    end

    assert(debug_messages.any? { |m| m.include?('Downloaded') })
  end

  def test_calls_on_debug_for_cache_hits
    debug_messages = []

    with_temp_config do |dir|
      files_dir = File.join(dir, 'cache', 'slk', 'files', 'test')
      FileUtils.mkdir_p(files_dir)
      File.write(File.join(files_dir, 'F123_image.png'), 'CACHED')

      downloader = Slk::Services::FileDownloader.new(
        cache_dir: File.join(dir, 'cache', 'slk'),
        on_debug: ->(msg) { debug_messages << msg }
      )
      workspace = mock_workspace
      message = build_message(files: [
                                { 'id' => 'F123', 'name' => 'image.png', 'url_private_download' => 'https://files.slack.com/nope' }
                              ])

      downloader.download_message_files([message], workspace)
    end

    assert(debug_messages.any? { |m| m.include?('Skipping') })
  end

  def test_handles_network_error_gracefully
    with_temp_config do |dir|
      downloader = build_downloader(dir)
      workspace = mock_workspace
      message = build_message(files: [
                                { 'id' => 'F123', 'name' => 'img.png', 'url_private_download' => 'https://files.slack.com/img.png' }
                              ])

      with_stub_http_error(Errno::ECONNREFUSED) do
        paths = downloader.download_message_files([message], workspace)

        assert_empty paths
      end
    end
  end

  def test_creates_workspace_subdirectory
    with_temp_config do |dir|
      downloader = build_downloader(dir)
      workspace = mock_workspace('myworkspace')
      message = build_message(files: [
                                { 'id' => 'F123', 'name' => 'img.png', 'url_private_download' => 'https://files.slack.com/img.png' }
                              ])

      with_stub_http(mock_success('DATA')) do
        paths = downloader.download_message_files([message], workspace)

        assert paths['F123'].include?('/files/myworkspace/')
      end
    end
  end

  def test_applies_auth_headers
    captured_requests = []

    with_temp_config do |dir|
      downloader = build_downloader(dir)
      workspace = mock_workspace('test', 'xoxb-my-secret-token')
      message = build_message(files: [
                                { 'id' => 'F123', 'name' => 'img.png', 'url_private_download' => 'https://files.slack.com/img.png' }
                              ])

      with_stub_http(mock_success('DATA'), capture: captured_requests) do
        downloader.download_message_files([message], workspace)
      end
    end

    assert(captured_requests.any? { |r| r['Authorization'] == 'Bearer xoxb-my-secret-token' })
  end

  def test_multiple_messages_with_mixed_files
    with_temp_config do |dir|
      downloader = build_downloader(dir)
      workspace = mock_workspace
      msg1 = build_message(
        files: [{ 'id' => 'F1', 'name' => 'a.png', 'url_private_download' => 'https://files.slack.com/a.png' }]
      )
      msg2 = build_message(
        files: [{ 'id' => 'F2', 'name' => 'b.png', 'url_private_download' => 'https://files.slack.com/b.png' }],
        attachments: [{ 'image_url' => 'https://cdn.example.com/c.jpg' }]
      )

      with_stub_http(mock_success('DATA')) do
        paths = downloader.download_message_files([msg1, msg2], workspace)

        assert paths.key?('F1')
        assert paths.key?('F2')
        assert paths.key?('att_1234567890.123456_0')
        assert_equal 3, paths.size
      end
    end
  end

  private

  def build_downloader(dir)
    Slk::Services::FileDownloader.new(cache_dir: File.join(dir, 'cache', 'slk'))
  end

  def build_message(files: [], attachments: [])
    Slk::Models::Message.new(
      ts: '1234567890.123456',
      user_id: 'U123',
      text: 'test message',
      files: files,
      attachments: attachments
    )
  end

  def mock_success(body)
    response = Net::HTTPSuccess.allocate
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

  def mock_redirect(location)
    response = Net::HTTPFound.allocate
    response.instance_variable_set(:@header, { 'location' => [location] })
    response
  end

  # Stub Net::HTTP.new to return a fake that always gives the same response
  def with_stub_http(response, capture: nil)
    original_new = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) do |*_args|
      StubHTTP.new(lambda { |req|
        capture&.push(req)
        response
      })
    end
    yield
  ensure
    Net::HTTP.define_singleton_method(:new, original_new)
  end

  # Stub Net::HTTP.new to return responses from a list in order
  def with_stub_http_sequence(responses)
    idx = 0
    original_new = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) do |*_args|
      StubHTTP.new(lambda { |_req|
        result = responses[idx]
        idx += 1
        result
      })
    end
    yield
  ensure
    Net::HTTP.define_singleton_method(:new, original_new)
  end

  # Stub Net::HTTP.new to always raise an error
  def with_stub_http_error(error_class)
    original_new = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) do |*_args|
      StubHTTP.new(->(_req) { raise error_class })
    end
    yield
  ensure
    Net::HTTP.define_singleton_method(:new, original_new)
  end

  # Fake HTTP client that delegates request() to a lambda
  class StubHTTP
    attr_writer :use_ssl, :verify_mode, :cert_store, :open_timeout, :read_timeout

    def initialize(handler)
      @handler = handler
    end

    def request(req) = @handler.call(req)
    def use_ssl? = false
    def cert_store = nil
    def start = self
    def started? = true
  end
end
