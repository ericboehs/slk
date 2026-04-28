# frozen_string_literal: true

require 'test_helper'

class HelpFormatterTest < Minitest::Test
  def setup
    @help = Slk::Support::HelpFormatter.new('slk foo [options]')
  end

  def test_render_with_just_usage
    out = @help.render
    assert_includes out, 'USAGE: slk foo [options]'
  end

  def test_description_appears_in_render
    @help.description('Do foo')
    out = @help.render
    assert_includes out, 'Do foo'
  end

  def test_notes_appear_in_render
    @help.note('Note 1')
    @help.note('Note 2')
    out = @help.render
    assert_includes out, 'Note 1'
    assert_includes out, 'Note 2'
  end

  def test_section_with_options
    @help.section('OPTIONS') do |s|
      s.option('-n, --num N', 'Number')
      s.option('-q, --quiet', 'Quiet')
    end
    out = @help.render
    assert_includes out, 'OPTIONS:'
    assert_includes out, '-n, --num N'
    assert_includes out, 'Number'
  end

  def test_section_with_examples_and_items_and_text
    @help.section('EXAMPLES') do |s|
      s.example('slk foo', 'Run foo')
      s.example('slk foo bar') # no description
      s.text('Some prose text')
      s.action('start', 'Start something')
      s.item('@user', 'A handle')
    end
    out = @help.render
    assert_includes out, 'slk foo'
    assert_includes out, 'Run foo'
    assert_includes out, 'slk foo bar'
    assert_includes out, 'Some prose text'
    assert_includes out, 'A handle'
  end

  def test_empty_section_renders_nothing
    @help.section('EMPTY') { |_s| nil }
    out = @help.render
    assert_includes out, 'EMPTY:'
    # No item lines beyond title
  end

  def test_chains_returning_self
    result = @help.description('x').note('y')
    assert_same @help, result
  end

  def test_section_aligns_columns
    @help.section('OPTIONS') do |s|
      s.option('-n', 'Short')
      s.option('--very-long-flag', 'Long')
    end
    out = @help.render
    short_idx = out.index('Short')
    long_idx = out.index('Long')
    refute_nil short_idx
    refute_nil long_idx
  end
end
