# frozen_string_literal: true

require 'test_helper'

class UserPickerTest < Minitest::Test
  def setup
    @output = test_output
    @prompt = StringIO.new
  end

  def picker(stdin:)
    Slk::Services::UserPicker.new(output: @output, stdin: stdin, prompt_io: @prompt)
  end

  def user(id, **attrs)
    profile = {
      'real_name' => attrs[:real], 'display_name' => attrs[:display],
      'title' => attrs[:title]
    }.compact
    { 'id' => id, 'name' => attrs[:name], 'deleted' => attrs[:deleted],
      'is_bot' => attrs[:bot], 'profile' => profile }.compact
  end

  def tty_stdin(input)
    stdin = StringIO.new(input)
    stdin.define_singleton_method(:tty?) { true }
    stdin
  end

  def non_tty_stdin
    stdin = StringIO.new
    stdin.define_singleton_method(:tty?) { false }
    stdin
  end

  def test_returns_only_match_without_prompting
    matches = [user('U1', real: 'Alice')]
    assert_equal 'U1', picker(stdin: non_tty_stdin).pick(matches)
  end

  def test_raises_in_non_tty_when_multiple_matches
    matches = [user('U1', real: 'Alice'), user('U2', real: 'Alice')]
    err = assert_raises(Slk::ApiError) { picker(stdin: non_tty_stdin).pick(matches) }
    assert_match(/Ambiguous match.*U1.*U2/, err.message)
    assert_match(/--pick.*--all/, err.message)
  end

  def test_prompts_and_returns_chosen_match_in_tty
    matches = [user('U1', real: 'Alice', title: 'Eng'),
               user('U2', real: 'Alice', deleted: true)]
    chosen = picker(stdin: tty_stdin("2\n")).pick(matches)
    assert_equal 'U2', chosen
    listing = @output.instance_variable_get(:@io).string
    assert_includes listing, '[1] Alice (U1) — Eng'
    assert_includes listing, '[2] Alice (U2) [deactivated]'
  end

  def test_reprompts_on_invalid_choice
    matches = [user('U1', real: 'Alice'), user('U2', real: 'Alice')]
    chosen = picker(stdin: tty_stdin("foo\n5\n1\n")).pick(matches)
    assert_equal 'U1', chosen
    assert_equal 3, @prompt.string.scan('Choice').size
  end

  def test_raises_on_eof
    matches = [user('U1', real: 'Alice'), user('U2', real: 'Alice')]
    assert_raises(Slk::ApiError) { picker(stdin: tty_stdin('')).pick(matches) }
  end

  def test_describes_bot_flag
    matches = [user('U1', real: 'Alice'),
               user('B1', name: 'helperbot', bot: true)]
    picker(stdin: tty_stdin("2\n")).pick(matches)
    listing = @output.instance_variable_get(:@io).string
    assert_includes listing, '[bot]'
  end
end
