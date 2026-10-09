# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'

class ImagePreviewTest < Minitest::Test
  # Host with terminal detection pinned so tests don't depend on the real env
  class Host
    include Slk::Support::InlineImages
    include Slk::Support::ImagePreview

    attr_accessor :kitty, :iterm, :tmux, :rendered

    def kitty_graphics_supported? = kitty
    def iterm2_protocol_supported? = iterm
    def in_tmux? = tmux
    def terminal_columns = 80

    def preview(path) = print_image_preview(path)
    def args(path) = chafa_args(path, 2)
    def format = image_preview_format
    def previewable?(path) = previewable_image?(path)
    def disabled_by_env? = image_previews_disabled_by_env?
    def supported? = image_previews_supported?

    private

    def render_image_preview(_path, _indent) = rendered
  end

  def setup
    @host = Host.new
    @dir = Dir.mktmpdir
    @png = File.join(@dir, 'shot.png')
    File.binwrite(@png, 'png')
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_format_prefers_kitty
    @host.kitty = true
    @host.iterm = true
    assert_equal 'kitty', @host.format
  end

  def test_format_falls_back_to_iterm
    @host.iterm = true
    assert_equal 'iterm', @host.format
  end

  def test_format_nil_when_unsupported
    assert_nil @host.format
  end

  def test_chafa_args_use_tmux_passthrough_in_tmux
    @host.kitty = true
    @host.tmux = true
    args = @host.args(@png)

    assert_includes args, '--format=kitty'
    assert_includes args, '--passthrough=tmux'
    assert_includes args, '--size=77x15'
    assert_equal @png, args.last
  end

  def test_chafa_args_skip_passthrough_outside_tmux
    @host.kitty = true
    refute_includes @host.args(@png), '--passthrough=tmux'
  end

  def test_env_disables_previews
    %w[0 false NO off].each do |value|
      with_preview_env(value) { assert Host.new.disabled_by_env?, "expected #{value} to disable" }
    end
  end

  def test_env_unset_or_truthy_keeps_previews_enabled
    [nil, '', '1', 'true'].each do |value|
      with_preview_env(value) { refute Host.new.disabled_by_env? }
    end
  end

  def test_env_disable_short_circuits_support_check
    host = Host.new
    host.kitty = true
    with_preview_env('0') { refute host.supported? }
  end

  def test_previewable_image_by_extension
    assert @host.previewable?('/tmp/a.PNG')
    assert @host.previewable?('/tmp/a.jpeg')
    refute @host.previewable?('/tmp/a.pdf')
    refute @host.previewable?('/tmp/a.svg')
  end

  def test_print_image_preview_writes_indented_output
    @host.rendered = "IMG\n"
    printed = capture_io { assert @host.preview(@png) }.first

    assert_equal "  IMG\n", printed
  end

  def test_print_image_preview_adds_trailing_newline
    @host.rendered = 'IMG'
    printed = capture_io { @host.preview(@png) }.first

    assert_equal "  IMG\n", printed
  end

  def test_print_image_preview_false_when_render_fails
    @host.rendered = nil
    refute @host.preview(@png)
  end

  def test_print_image_preview_false_for_non_image
    pdf = File.join(@dir, 'doc.pdf')
    File.binwrite(pdf, 'pdf')
    @host.rendered = 'IMG'
    refute @host.preview(pdf)
  end

  def test_print_image_preview_false_for_missing_file
    @host.rendered = 'IMG'
    refute @host.preview(File.join(@dir, 'missing.png'))
  end

  private

  def with_preview_env(value)
    old = ENV.fetch('SLK_IMAGE_PREVIEW', nil)
    value.nil? ? ENV.delete('SLK_IMAGE_PREVIEW') : ENV['SLK_IMAGE_PREVIEW'] = value
    yield
  ensure
    old.nil? ? ENV.delete('SLK_IMAGE_PREVIEW') : ENV['SLK_IMAGE_PREVIEW'] = old
  end
end
