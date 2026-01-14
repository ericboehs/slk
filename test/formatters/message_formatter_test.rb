# frozen_string_literal: true

require 'test_helper'

class MessageFormatterTest < Minitest::Test
  def setup
    @io = StringIO.new
    @err = StringIO.new
    @output = SlackCli::Formatters::Output.new(io: @io, err: @err, color: false)
    @mention_replacer = SlackCli::Formatters::MentionReplacer.new(cache_store: MockCache.new)
    @emoji_replacer = SlackCli::Formatters::EmojiReplacer.new
    @cache = MockCache.new
    @formatter = SlackCli::Formatters::MessageFormatter.new(
      output: @output,
      mention_replacer: @mention_replacer,
      emoji_replacer: @emoji_replacer,
      cache_store: @cache
    )
  end

  def test_format_json_includes_basic_fields
    message = create_message(
      ts: '1234567890.123456',
      user: 'U123ABC',
      text: 'Hello world'
    )
    workspace = mock_workspace('test')

    result = @formatter.format_json(message, workspace: workspace)

    assert_equal '1234567890.123456', result[:ts]
    assert_equal 'U123ABC', result[:user_id]
    assert_equal 'Hello world', result[:text]
  end

  def test_format_json_includes_resolved_user_name
    @cache.set_user('test', 'U123ABC', 'john.doe')
    message = create_message(user: 'U123ABC', text: 'Hi')
    workspace = mock_workspace('test')

    result = @formatter.format_json(message, workspace: workspace)

    assert_equal 'john.doe', result[:user_name]
  end

  def test_format_json_omits_user_name_when_no_names_option
    @cache.set_user('test', 'U123ABC', 'john.doe')
    message = create_message(user: 'U123ABC', text: 'Hi')
    workspace = mock_workspace('test')

    result = @formatter.format_json(message, workspace: workspace, options: { no_names: true })

    refute result.key?(:user_name)
  end

  def test_format_json_includes_channel_info_when_provided
    @cache.set_channel('test', 'general', 'C123ABC')
    message = create_message(text: 'Test')
    workspace = mock_workspace('test')

    result = @formatter.format_json(message, workspace: workspace, options: { channel_id: 'C123ABC' })

    assert_equal 'C123ABC', result[:channel_id]
    assert_equal 'general', result[:channel_name]
  end

  def test_format_json_includes_reactions_with_user_objects
    @cache.set_user('test', 'U111AAA', 'alice')
    @cache.set_user('test', 'U222BBB', 'bob')

    message = create_message_with_reactions(
      text: 'Great idea!',
      reactions: [
        { 'name' => 'thumbsup', 'count' => 2, 'users' => ['U111AAA', 'U222BBB'] }
      ]
    )
    workspace = mock_workspace('test')

    result = @formatter.format_json(message, workspace: workspace)

    assert_equal 1, result[:reactions].size
    reaction = result[:reactions].first
    assert_equal 'thumbsup', reaction[:name]
    assert_equal 2, reaction[:count]
    assert_equal 2, reaction[:users].size

    # Users should be objects with id and name
    user1 = reaction[:users].find { |u| u[:id] == 'U111AAA' }
    assert_equal 'alice', user1[:name]

    user2 = reaction[:users].find { |u| u[:id] == 'U222BBB' }
    assert_equal 'bob', user2[:name]
  end

  def test_format_json_includes_reaction_timestamps
    message = create_message_with_reaction_timestamps(
      text: 'Test',
      reactions: [
        {
          'name' => 'fire',
          'count' => 1,
          'users' => ['U123ABC'],
          'user_timestamps' => { 'U123ABC' => '1704067200.000000' }
        }
      ]
    )
    workspace = mock_workspace('test')

    result = @formatter.format_json(message, workspace: workspace, options: { reaction_timestamps: true })

    reaction = result[:reactions].first
    user = reaction[:users].first
    assert_equal '1704067200.000000', user[:reacted_at]
    assert user[:reacted_at_iso8601]
  end

  def test_format_json_includes_thread_info
    message = create_message_with_thread(
      ts: '1234567890.123456',
      thread_ts: '1234567890.123456',
      text: 'Thread parent',
      reply_count: 5
    )
    workspace = mock_workspace('test')

    result = @formatter.format_json(message, workspace: workspace)

    assert_equal '1234567890.123456', result[:thread_ts]
    assert_equal 5, result[:reply_count]
  end

  private

  def create_message(ts: '1234567890.123456', user: 'U123ABC', text: 'Hello', thread_ts: nil)
    data = {
      'ts' => ts,
      'user' => user,
      'text' => text,
      'thread_ts' => thread_ts
    }
    SlackCli::Models::Message.from_api(data)
  end

  def create_message_with_reactions(text:, reactions:)
    data = {
      'ts' => '1234567890.123456',
      'user' => 'U123ABC',
      'text' => text,
      'reactions' => reactions
    }
    SlackCli::Models::Message.from_api(data)
  end

  def create_message_with_thread(ts:, thread_ts:, text:, reply_count:)
    data = {
      'ts' => ts,
      'user' => 'U123ABC',
      'text' => text,
      'thread_ts' => thread_ts,
      'reply_count' => reply_count
    }
    SlackCli::Models::Message.from_api(data)
  end

  def create_message_with_reaction_timestamps(text:, reactions:)
    # Build reactions with timestamps using with_timestamps
    built_reactions = reactions.map do |r|
      reaction = SlackCli::Models::Reaction.from_api({
        'name' => r['name'],
        'count' => r['count'],
        'users' => r['users']
      })
      if r['user_timestamps']
        reaction = reaction.with_timestamps(r['user_timestamps'])
      end
      reaction
    end

    # Create message data without reactions, then create message with reactions
    data = {
      'ts' => '1234567890.123456',
      'user' => 'U123ABC',
      'text' => text,
      'reactions' => []
    }
    base_message = SlackCli::Models::Message.from_api(data)

    # Return new message with our custom reactions
    SlackCli::Models::Message.new(
      ts: base_message.ts,
      user_id: base_message.user_id,
      text: base_message.text,
      reactions: built_reactions,
      reply_count: base_message.reply_count,
      thread_ts: base_message.thread_ts,
      files: base_message.files,
      attachments: base_message.attachments,
      blocks: base_message.blocks,
      user_profile: base_message.user_profile,
      bot_profile: base_message.bot_profile,
      username: base_message.username,
      subtype: base_message.subtype,
      channel_id: base_message.channel_id
    )
  end

  # Simple mock cache for testing
  class MockCache
    def initialize
      @users = {}
      @channels = {}
      @channel_ids = {}
    end

    def get_user(workspace, user_id)
      @users["#{workspace}:#{user_id}"]
    end

    def set_user(workspace, user_id, name, persist: false)
      @users["#{workspace}:#{user_id}"] = name
    end

    def get_channel_name(workspace, channel_id)
      @channel_ids["#{workspace}:#{channel_id}"]
    end

    def set_channel(workspace, name, channel_id)
      @channels["#{workspace}:#{name}"] = channel_id
      @channel_ids["#{workspace}:#{channel_id}"] = name
    end

    def get_channel_id(workspace, name)
      @channels["#{workspace}:#{name}"]
    end
  end
end
