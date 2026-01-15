# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'

class InlineImagesTest < Minitest::Test
  include Slk::Support::InlineImages

  def test_inline_images_supported_with_iterm
    with_env('TERM_PROGRAM' => 'iTerm.app') do
      assert inline_images_supported?
    end
  end

  def test_inline_images_supported_with_wezterm
    with_env('TERM_PROGRAM' => 'WezTerm') do
      assert inline_images_supported?
    end
  end

  def test_inline_images_supported_with_lc_terminal_iterm
    with_env('LC_TERMINAL' => 'iTerm2') do
      assert inline_images_supported?
    end
  end

  def test_inline_images_supported_with_mintty
    with_env('TERM' => 'mintty') do
      assert inline_images_supported?
    end
  end

  def test_inline_images_not_supported_with_other_terminal
    with_env('TERM_PROGRAM' => 'Apple_Terminal', 'LC_TERMINAL' => nil, 'TERM' => 'xterm-256color') do
      refute inline_images_supported?
    end
  end

  def test_in_tmux_with_screen_term
    with_env('TERM' => 'screen-256color') do
      assert in_tmux?
    end
  end

  def test_in_tmux_with_tmux_term
    with_env('TERM' => 'tmux-256color') do
      assert in_tmux?
    end
  end

  def test_not_in_tmux_with_xterm
    with_env('TERM' => 'xterm-256color') do
      refute in_tmux?
    end
  end

  def test_print_inline_image_returns_nil_for_nonexistent_file
    result = print_inline_image('/nonexistent/file.png')
    assert_nil result
  end

  def test_print_inline_image_handles_unreadable_file
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'test.png')
      File.write(file, 'fake image data')

      # Make file unreadable
      File.chmod(0o000, file)

      # Should not raise, just return nil
      result = print_inline_image(file)
      assert_nil result
    ensure
      # Restore permissions for cleanup
      File.chmod(0o644, file) if File.exist?(file)
    end
  end

  def test_print_inline_image_with_text_returns_false_when_not_supported
    with_env('TERM_PROGRAM' => 'Apple_Terminal', 'LC_TERMINAL' => nil, 'TERM' => 'xterm') do
      result = print_inline_image_with_text('/some/file.png', 'text')
      assert_equal false, result
    end
  end

  def test_print_inline_image_with_text_returns_false_for_nonexistent_file
    with_env('TERM_PROGRAM' => 'iTerm.app') do
      result = print_inline_image_with_text('/nonexistent/file.png', 'text')
      assert_equal false, result
    end
  end

  private

  def with_env(env_vars)
    old_values = {}
    env_vars.each do |key, value|
      old_values[key] = ENV.fetch(key, nil)
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
    yield
  ensure
    old_values.each do |key, value|
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end
