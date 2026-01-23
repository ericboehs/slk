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
end
