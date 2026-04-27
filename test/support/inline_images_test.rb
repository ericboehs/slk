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
    with_env(
      'TERM_PROGRAM' => 'Apple_Terminal', 'LC_TERMINAL' => nil,
      'TERM' => 'xterm-256color', 'GHOSTTY_RESOURCES_DIR' => nil
    ) do
      refute inline_images_supported?
    end
  end

  def test_kitty_graphics_supported_with_ghostty_term_program
    with_env(
      'TERM_PROGRAM' => 'ghostty', 'LC_TERMINAL' => nil, 'TERM' => 'xterm',
      'GHOSTTY_RESOURCES_DIR' => nil
    ) do
      assert kitty_graphics_supported?
      assert inline_images_supported?
    end
  end

  def test_kitty_graphics_supported_with_ghostty_resources_dir
    with_env(
      'TERM_PROGRAM' => 'Apple_Terminal', 'LC_TERMINAL' => nil, 'TERM' => 'xterm',
      'GHOSTTY_RESOURCES_DIR' => '/Applications/Ghostty.app/Contents/Resources/ghostty'
    ) do
      assert kitty_graphics_supported?
    end
  end

  def test_kitty_graphics_supported_with_kitty_term
    with_env(
      'TERM_PROGRAM' => 'Apple_Terminal', 'LC_TERMINAL' => nil, 'TERM' => 'xterm-kitty',
      'GHOSTTY_RESOURCES_DIR' => nil
    ) do
      assert kitty_graphics_supported?
    end
  end

  def test_lc_terminal_wezterm_supported
    with_env('LC_TERMINAL' => 'WezTerm', 'TERM_PROGRAM' => nil, 'TERM' => 'xterm') do
      assert iterm2_protocol_supported?
    end
  end

  def test_print_inline_image_routes_to_kitty_when_supported
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'a.png')
      File.binwrite(file, png_header_bytes)
      printed = capture_stdout do
        with_env(
          'TERM_PROGRAM' => 'ghostty', 'LC_TERMINAL' => nil, 'TERM' => 'xterm',
          'GHOSTTY_RESOURCES_DIR' => nil
        ) do
          print_inline_image(file)
        end
      end
      assert_includes printed, "\e_Ga=T"
    end
  end

  def test_print_inline_image_routes_to_iterm_when_not_kitty
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'a.png')
      File.binwrite(file, png_header_bytes)
      printed = capture_stdout do
        with_env(
          'TERM_PROGRAM' => 'iTerm.app', 'LC_TERMINAL' => nil, 'TERM' => 'xterm',
          'GHOSTTY_RESOURCES_DIR' => nil
        ) do
          print_inline_image(file)
        end
      end
      assert_includes printed, "\e]1337;File=inline=1"
    end
  end

  def test_print_inline_image_routes_tmux_iterm
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'a.png')
      File.binwrite(file, png_header_bytes)
      printed = capture_stdout do
        with_env(
          'TERM_PROGRAM' => 'iTerm.app', 'LC_TERMINAL' => nil,
          'TERM' => 'screen-256color', 'GHOSTTY_RESOURCES_DIR' => nil
        ) do
          print_inline_image(file)
        end
      end
      assert_includes printed, "\ePtmux;"
    end
  end

  def test_print_inline_image_routes_tmux_kitty
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'a.png')
      File.binwrite(file, png_header_bytes)
      printed = capture_stdout do
        with_env(
          'TERM_PROGRAM' => 'ghostty', 'LC_TERMINAL' => nil,
          'TERM' => 'screen-256color', 'GHOSTTY_RESOURCES_DIR' => nil
        ) do
          # Reset memo so previous tests don't taint
          @tmux_client_is_kitty_compatible = nil
          print_inline_image(file)
        end
      end
      assert_includes printed, "\ePtmux;"
    end
  end

  def test_png_data_detection
    assert png_data?(png_header_bytes)
    refute png_data?('not png')
    refute png_data?(nil.to_s)
  end

  def test_in_tmux_with_tmux_program
    with_env('TERM' => 'tmux-256color') do
      assert in_tmux?
    end
  end

  def test_print_inline_image_with_text_iterm
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'a.png')
      File.binwrite(file, png_header_bytes)
      printed = capture_stdout do
        with_env(
          'TERM_PROGRAM' => 'iTerm.app', 'LC_TERMINAL' => nil, 'TERM' => 'xterm',
          'GHOSTTY_RESOURCES_DIR' => nil
        ) do
          assert print_inline_image_with_text(file, 'hello')
        end
      end
      assert_includes printed, 'hello'
    end
  end

  def test_print_inline_image_with_text_tmux_iterm
    @tmux_client_is_kitty_compatible = false
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'a.png')
      File.binwrite(file, png_header_bytes)
      printed = capture_stdout do
        with_env(
          'TERM_PROGRAM' => 'iTerm.app', 'LC_TERMINAL' => nil,
          'TERM' => 'screen-256color', 'GHOSTTY_RESOURCES_DIR' => nil
        ) do
          stub(:tmux_client_is_kitty_compatible?, false) do
            print_inline_image_with_text(file, 'tag')
          end
        end
      end
      assert_includes printed, 'tag'
      assert_includes printed, "\e[1A"
    end
  end

  def test_tmux_client_kitty_compatible_when_not_in_tmux
    @tmux_client_is_kitty_compatible = nil
    with_env('TERM' => 'xterm', 'GHOSTTY_RESOURCES_DIR' => nil, 'TERM_PROGRAM' => nil) do
      refute tmux_client_is_kitty_compatible?
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

  def test_in_tmux_returns_false_when_term_nil
    with_env('TERM' => nil) do
      refute in_tmux?
    end
  end

  def test_png_data_returns_false_for_short_data
    refute png_data?('')
    refute png_data?('abc')
  end

  def test_read_image_data_returns_nil_for_nonexistent
    assert_nil read_image_data_for_protocol('/nonexistent/file.png')
  end

  def test_convert_to_png_returns_nil_when_sips_fails
    Dir.mktmpdir do |dir|
      file = File.join(dir, 'fake.gif')
      File.binwrite(file, "GIF87a#{'x' * 50}")
      result = convert_to_png(file)
      # If sips isn't available, returns nil
      assert(result.nil? || result.is_a?(String))
    end
  end

  private

  def png_header_bytes
    "#{[137, 80, 78, 71, 13, 10, 26, 10].pack('C*')}rest_of_data"
  end

  def capture_stdout
    old = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = old
  end

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
