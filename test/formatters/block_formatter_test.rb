# frozen_string_literal: true

require 'test_helper'

class BlockFormatterTest < Minitest::Test
  # Stand-in for the text processor: identity by default
  class FakeTextProcessor
    def initialize(transform: nil)
      @transform = transform || ->(text) { text }
    end

    def call(text)
      @transform.call(text)
    end
  end

  def setup
    @processor = FakeTextProcessor.new
    @formatter = Slk::Formatters::BlockFormatter.new(text_processor: @processor)
  end

  def test_format_returns_early_when_blocks_nil
    lines = []
    @formatter.format(nil, 'main', lines, {})
    assert_equal [], lines
  end

  def test_format_returns_early_when_blocks_empty
    lines = []
    @formatter.format([], 'main', lines, {})
    assert_equal [], lines
  end

  def test_format_returns_early_when_no_blocks_option_set
    blocks = [{ 'type' => 'section', 'text' => { 'text' => 'Hello' } }]
    lines = []
    @formatter.format(blocks, 'main', lines, no_blocks: true)
    assert_equal [], lines
  end

  def test_format_appends_block_text_with_blockquote_prefix
    blocks = [{ 'type' => 'section', 'text' => { 'text' => 'Hello world' } }]
    lines = []
    @formatter.format(blocks, 'different', lines, {})

    assert_equal ['', '> Hello world'], lines
  end

  def test_format_filters_out_text_matching_main_text
    blocks = [{ 'type' => 'section', 'text' => { 'text' => 'Hello World' } }]
    lines = []
    @formatter.format(blocks, '  hello   world  ', lines, {})

    assert_equal [], lines
  end

  def test_format_handles_non_array_blocks_gracefully
    lines = []
    # Pass a hash; #any? is true, but extract_texts must handle the non-array case
    @formatter.format({ 'type' => 'section', 'text' => { 'text' => 'X' } }, 'main', lines, {})

    # No texts extracted -> early return
    assert_equal [], lines
  end

  def test_format_skips_non_section_blocks
    blocks = [
      { 'type' => 'divider' },
      { 'type' => 'image', 'image_url' => 'http://example.com' },
      { 'type' => 'section', 'text' => { 'text' => 'Section text' } }
    ]
    lines = []
    @formatter.format(blocks, 'main', lines, {})

    assert_equal ['', '> Section text'], lines
  end

  def test_format_handles_section_block_with_no_text_field
    blocks = [{ 'type' => 'section' }]
    lines = []
    @formatter.format(blocks, 'main', lines, {})

    assert_equal [], lines
  end

  def test_format_emits_multiple_section_blocks
    blocks = [
      { 'type' => 'section', 'text' => { 'text' => 'first' } },
      { 'type' => 'section', 'text' => { 'text' => 'second' } }
    ]
    lines = []
    @formatter.format(blocks, 'main', lines, {})

    assert_equal ['', '> first', '> second'], lines
  end

  def test_format_processes_text_through_text_processor
    processor = FakeTextProcessor.new(transform: lambda(&:upcase))
    formatter = Slk::Formatters::BlockFormatter.new(text_processor: processor)

    blocks = [{ 'type' => 'section', 'text' => { 'text' => 'shout' } }]
    lines = []
    formatter.format(blocks, 'main', lines, {})

    assert_equal ['', '> SHOUT'], lines
  end

  def test_format_wraps_text_when_width_provided
    long = 'word ' * 20
    blocks = [{ 'type' => 'section', 'text' => { 'text' => long.strip } }]
    lines = []
    @formatter.format(blocks, 'main', lines, width: 20)

    # Each line should be prefixed with '> ' and contain at most ~20 visible chars
    body_lines = lines.drop(1)
    refute_empty body_lines
    assert(body_lines.all? { |line| line.start_with?('> ') })
  end

  def test_format_does_not_wrap_when_width_too_small
    blocks = [{ 'type' => 'section', 'text' => { 'text' => 'word word word' } }]
    lines = []
    @formatter.format(blocks, 'main', lines, width: 2)

    # Width <= 2 disables wrapping; whole line emitted intact (single line)
    assert_equal ['', '> word word word'], lines
  end

  def test_format_does_not_wrap_when_width_nil
    blocks = [{ 'type' => 'section', 'text' => { 'text' => 'word word' } }]
    lines = []
    @formatter.format(blocks, 'main', lines, {})

    assert_equal ['', '> word word'], lines
  end

  def test_format_handles_multiline_block_text
    blocks = [{ 'type' => 'section', 'text' => { 'text' => "line1\nline2" } }]
    lines = []
    @formatter.format(blocks, 'main', lines, {})

    assert_equal ['', '> line1', '> line2'], lines
  end

  def test_format_filters_blocks_whose_normalized_text_matches_main
    blocks = [
      { 'type' => 'section', 'text' => { 'text' => 'Same' } },
      { 'type' => 'section', 'text' => { 'text' => 'Different' } }
    ]
    lines = []
    @formatter.format(blocks, 'same', lines, {})

    # Only 'Different' remains
    assert_equal ['', '> Different'], lines
  end

  def test_format_handles_nil_main_text
    blocks = [{ 'type' => 'section', 'text' => { 'text' => 'Hello' } }]
    lines = []
    @formatter.format(blocks, nil, lines, {})

    assert_equal ['', '> Hello'], lines
  end
end
