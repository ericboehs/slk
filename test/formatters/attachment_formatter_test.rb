# frozen_string_literal: true

require_relative '../test_helper'

class AttachmentFormatterTest < Minitest::Test
  def setup
    @io = StringIO.new
    @err = StringIO.new
    @output = Slk::Formatters::Output.new(io: @io, err: @err, color: false)
    @text_processor = ->(text) { text } # Pass-through processor
    @formatter = Slk::Formatters::AttachmentFormatter.new(
      output: @output,
      text_processor: @text_processor
    )
  end

  def test_format_empty_attachments
    lines = []

    @formatter.format([], lines, {})

    assert_empty lines
  end

  def test_format_with_no_attachments_option
    attachments = [{ 'text' => 'Some text' }]
    lines = []

    @formatter.format(attachments, lines, { no_attachments: true })

    assert_empty lines
  end

  def test_format_attachment_with_text
    attachments = [{ 'text' => 'Attachment text content' }]
    lines = []

    @formatter.format(attachments, lines, {})

    assert(lines.any? { |l| l.include?('Attachment text content') })
  end

  def test_format_attachment_with_fallback
    attachments = [{ 'fallback' => 'Fallback text' }]
    lines = []

    @formatter.format(attachments, lines, {})

    assert(lines.any? { |l| l.include?('Fallback text') })
  end

  def test_format_attachment_with_author
    attachments = [{ 'author_name' => 'John Doe', 'text' => 'Content' }]
    lines = []

    @formatter.format(attachments, lines, {})

    assert(lines.any? { |l| l.include?('John Doe') })
  end

  def test_format_attachment_with_image_url
    attachments = [{ 'image_url' => 'https://example.com/image.png', 'title' => 'My Image' }]
    lines = []

    @formatter.format(attachments, lines, {})

    assert(lines.any? { |l| l.include?('[Image: My Image]') })
  end

  def test_format_attachment_with_thumb_url
    attachments = [{ 'thumb_url' => 'https://example.com/thumb.jpg' }]
    lines = []

    @formatter.format(attachments, lines, {})

    assert(lines.any? { |l| l.include?('[Image:') })
  end

  def test_format_attachment_extracts_filename_from_url
    attachments = [{ 'image_url' => 'https://example.com/path/to/screenshot.png' }]
    lines = []

    @formatter.format(attachments, lines, {})

    assert(lines.any? { |l| l.include?('[Image: screenshot.png]') })
  end

  def test_unfurl_title_author_text_and_block_image_title_use_text_processor
    passthrough = Object.new
    passthrough.define_singleton_method(:replace) { |text, _workspace| text }
    processor = Slk::Formatters::TextProcessor.new(mention_replacer: passthrough, emoji_replacer: passthrough)
    workspace = mock_workspace('test')
    formatter = Slk::Formatters::AttachmentFormatter.new(
      output: @output, text_processor: ->(text) { processor.process(text, workspace) }
    )
    attachments = [
      { 'author_name' => 'Author &amp; Friend', 'text' => 'A &lt; B &amp; C &gt; D',
        'title' => 'Models &amp; Tools', 'image_url' => 'https://example.com/image.png' },
      { 'blocks' => [{ 'type' => 'image', 'title' => { 'text' => 'One &amp; Two' } }] }
    ]
    lines = []

    formatter.format(attachments, lines, {})

    assert_includes lines, '> Author & Friend:'
    assert_includes lines, '> A < B & C > D'
    assert_includes lines, '> [Image: Models & Tools]'
    assert_includes lines, '> [Image: One & Two]'
    refute(lines.any? { |line| line.include?('&amp;') })
  end

  def test_format_attachment_with_block_images
    attachments = [{
      'blocks' => [
        { 'type' => 'image', 'title' => { 'text' => 'Screenshot 1' } },
        { 'type' => 'image', 'title' => { 'text' => 'Screenshot 2' } }
      ]
    }]
    lines = []

    @formatter.format(attachments, lines, {})

    assert(lines.any? { |l| l.include?('[Image: Screenshot 1]') })
    assert(lines.any? { |l| l.include?('[Image: Screenshot 2]') })
  end

  def test_format_attachment_block_image_without_title
    attachments = [{
      'blocks' => [
        { 'type' => 'image' }
      ]
    }]
    lines = []

    @formatter.format(attachments, lines, {})

    assert(lines.any? { |l| l.include?('[Image: Image]') })
  end

  def test_extract_block_images_returns_empty_for_no_blocks
    result = @formatter.send(:extract_block_images, {})

    assert_empty result
  end

  def test_extract_block_images_ignores_non_image_blocks
    attachment = {
      'blocks' => [
        { 'type' => 'section', 'text' => { 'text' => 'Some text' } },
        { 'type' => 'divider' },
        { 'type' => 'image', 'title' => { 'text' => 'Only Image' } }
      ]
    }

    result = @formatter.send(:extract_block_images, attachment)

    assert_equal 1, result.length
    assert_equal 'Only Image', result.first
  end

  def test_format_attachment_skips_text_when_block_images_present
    attachments = [{
      'text' => 'This text should not appear',
      'blocks' => [
        { 'type' => 'image', 'title' => { 'text' => 'Image Only' } }
      ]
    }]
    lines = []

    @formatter.format(attachments, lines, {})

    refute(lines.any? { |l| l.include?('This text should not appear') })
    assert(lines.any? { |l| l.include?('[Image: Image Only]') })
  end

  def test_format_attachment_with_text_wrapping
    long_text = 'This is a very long text that should be wrapped at the specified width for better readability'
    attachments = [{ 'text' => long_text }]
    lines = []

    @formatter.format(attachments, lines, { width: 40 })

    # Should have multiple lines due to wrapping
    text_lines = lines.select { |l| l.start_with?('> ') }
    assert text_lines.length >= 1
  end

  def test_format_attachment_without_content_is_skipped
    attachments = [{ 'some_other_field' => 'value' }]
    lines = []

    @formatter.format(attachments, lines, {})

    # Should only have the empty line separator at most, or nothing
    assert lines.empty? || lines.all?(&:empty?)
  end

  def test_extract_filename_handles_invalid_uri
    result = @formatter.send(:extract_filename, 'not a valid uri %%%')

    assert_equal 'image', result
  end

  def test_format_multiple_attachments
    attachments = [
      { 'text' => 'First attachment' },
      { 'text' => 'Second attachment' }
    ]
    lines = []

    @formatter.format(attachments, lines, {})

    assert(lines.any? { |l| l.include?('First attachment') })
    assert(lines.any? { |l| l.include?('Second attachment') })
  end

  def test_format_attachment_uses_text_processor
    custom_processor = lambda(&:upcase)
    formatter = Slk::Formatters::AttachmentFormatter.new(
      output: @output,
      text_processor: custom_processor
    )
    attachments = [{ 'text' => 'lowercase text' }]
    lines = []

    formatter.format(attachments, lines, {})

    assert(lines.any? { |l| l.include?('LOWERCASE TEXT') })
  end

  def test_format_image_with_local_path
    attachments = [{ 'image_url' => 'https://example.com/img.png' }]
    lines = []
    options = { file_paths: { 'att_123_0' => '/local/cached.png' } }
    @formatter.format(attachments, lines, options, message_ts: '123')
    assert(lines.any? { |l| l.include?('/local/cached.png') })
  end

  def test_format_image_without_message_ts
    attachments = [{ 'image_url' => 'https://example.com/img.png' }]
    lines = []
    options = { file_paths: { 'att_123_0' => '/local/cached.png' } }
    @formatter.format(attachments, lines, options) # no message_ts
    refute(lines.any? { |l| l.include?('/local/cached.png') })
  end
end
