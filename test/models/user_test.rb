# frozen_string_literal: true

require 'test_helper'

class UserTest < Minitest::Test
  def test_basic_user
    user = SlackCli::Models::User.new(id: 'U12345ABC', name: 'jsmith')

    assert_equal 'U12345ABC', user.id
    assert_equal 'jsmith', user.name
    refute user.is_bot
  end

  def test_user_with_all_fields
    user = SlackCli::Models::User.new(
      id: 'U12345ABC',
      name: 'jsmith',
      real_name: 'John Smith',
      display_name: 'Johnny',
      is_bot: false
    )

    assert_equal 'John Smith', user.real_name
    assert_equal 'Johnny', user.display_name
  end

  def test_enterprise_grid_user_id
    user = SlackCli::Models::User.new(id: 'W12345ABC')
    assert_equal 'W12345ABC', user.id
  end

  def test_from_api
    data = {
      'id' => 'U123ABC',
      'name' => 'testuser',
      'real_name' => 'Test User',
      'profile' => {
        'display_name' => 'testy',
        'real_name' => 'Test User Profile'
      },
      'is_bot' => true
    }

    user = SlackCli::Models::User.from_api(data)

    assert_equal 'U123ABC', user.id
    assert_equal 'testuser', user.name
    assert_equal 'testy', user.display_name
    assert user.is_bot
  end

  def test_best_name_prefers_display_name
    user = SlackCli::Models::User.new(
      id: 'U12345ABC',
      name: 'jsmith',
      real_name: 'John Smith',
      display_name: 'Johnny'
    )

    assert_equal 'Johnny', user.best_name
  end

  def test_best_name_falls_back_to_real_name
    user = SlackCli::Models::User.new(
      id: 'U12345ABC',
      name: 'jsmith',
      real_name: 'John Smith',
      display_name: ''
    )

    assert_equal 'John Smith', user.best_name
  end

  def test_best_name_falls_back_to_name
    user = SlackCli::Models::User.new(
      id: 'U12345ABC',
      name: 'jsmith'
    )

    assert_equal 'jsmith', user.best_name
  end

  def test_best_name_falls_back_to_id
    user = SlackCli::Models::User.new(id: 'U12345ABC')

    assert_equal 'U12345ABC', user.best_name
  end

  def test_mention
    user = SlackCli::Models::User.new(id: 'U12345ABC', display_name: 'Johnny')

    assert_equal '@Johnny', user.mention
  end

  def test_to_s
    user = SlackCli::Models::User.new(id: 'U12345ABC', display_name: 'Johnny')

    assert_equal 'Johnny', user.to_s
  end

  def test_values_are_frozen
    user = SlackCli::Models::User.new(id: 'U12345ABC', name: 'test')

    assert user.id.frozen?
    assert user.name.frozen?
  end

  def test_empty_id_raises
    assert_raises(ArgumentError) do
      SlackCli::Models::User.new(id: '')
    end
  end

  def test_whitespace_id_raises
    assert_raises(ArgumentError) do
      SlackCli::Models::User.new(id: '   ')
    end
  end

  def test_invalid_id_format_raises
    error = assert_raises(ArgumentError) do
      SlackCli::Models::User.new(id: 'invalid')
    end

    assert_match(/invalid user id format/i, error.message)
  end

  def test_lowercase_id_raises
    error = assert_raises(ArgumentError) do
      SlackCli::Models::User.new(id: 'u12345abc')
    end

    assert_match(/invalid user id format/i, error.message)
  end

  def test_bot_id_raises
    # Bot IDs start with B, not U or W
    error = assert_raises(ArgumentError) do
      SlackCli::Models::User.new(id: 'B12345ABC')
    end

    assert_match(/invalid user id format/i, error.message)
  end
end
