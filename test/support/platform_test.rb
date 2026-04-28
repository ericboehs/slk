# frozen_string_literal: true

require 'test_helper'
require 'slk/support/platform'

class PlatformTest < Minitest::Test
  Platform = Slk::Support::Platform

  ORIGINAL_WIN_PLATFORM = Gem.method(:win_platform?)

  def teardown
    Gem.define_singleton_method(:win_platform?, ORIGINAL_WIN_PLATFORM)
  end

  def test_windows_returns_true_when_gem_reports_windows
    stub_win_platform(true)
    assert Platform.windows?
  end

  def test_windows_returns_false_when_gem_reports_non_windows
    stub_win_platform(false)
    refute Platform.windows?
  end

  def test_macos_returns_true_for_darwin
    with_ruby_platform('x86_64-darwin23') do
      assert Platform.macos?
    end
  end

  def test_macos_returns_false_for_non_darwin
    with_ruby_platform('x86_64-linux') do
      refute Platform.macos?
    end
  end

  def test_linux_returns_true_for_linux
    with_ruby_platform('x86_64-linux') do
      assert Platform.linux?
    end
  end

  def test_linux_returns_false_for_non_linux
    with_ruby_platform('x86_64-darwin23') do
      refute Platform.linux?
    end
  end

  def test_open_url_uses_start_on_windows
    stub_win_platform(true)
    captured = capture_system_calls
    Platform.open_url('https://example.com')
    assert_equal [['start', '', 'https://example.com']], captured
  end

  def test_open_url_uses_open_on_macos
    stub_win_platform(false)
    with_ruby_platform('x86_64-darwin23') do
      captured = capture_system_calls
      Platform.open_url('https://example.com')
      assert_equal [['open', 'https://example.com']], captured
    end
  end

  def test_open_url_uses_xdg_open_on_linux
    stub_win_platform(false)
    with_ruby_platform('x86_64-linux') do
      captured = capture_system_calls
      Platform.open_url('https://example.com')
      assert_equal [['xdg-open', 'https://example.com']], captured
    end
  end

  private

  def stub_win_platform(value)
    Gem.define_singleton_method(:win_platform?) { value }
  end

  def with_ruby_platform(value)
    original = Object.send(:remove_const, :RUBY_PLATFORM)
    Object.const_set(:RUBY_PLATFORM, value)
    yield
  ensure
    Object.send(:remove_const, :RUBY_PLATFORM)
    Object.const_set(:RUBY_PLATFORM, original)
  end

  def capture_system_calls
    captured = []
    Platform.define_singleton_method(:system) do |*args|
      captured << args
      true
    end
    captured
  end
end
