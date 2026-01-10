# frozen_string_literal: true

require "test_helper"

class MentionReplacerTest < Minitest::Test
  def setup
    @cache = SlackCli::Services::CacheStore.new(paths: mock_paths)
    @replacer = SlackCli::Formatters::MentionReplacer.new(cache_store: @cache)
    @workspace = SlackCli::Models::Workspace.new(name: "test", token: "xoxp-test")
  end

  def mock_paths
    @mock_paths ||= begin
      paths = Object.new
      def paths.cache_dir
        @tmpdir ||= Dir.mktmpdir
      end
      def paths.cache_file(name)
        File.join(cache_dir, name)
      end
      def paths.ensure_cache_dir
        FileUtils.mkdir_p(cache_dir)
      end
      paths
    end
  end

  def teardown
    FileUtils.rm_rf(@mock_paths.cache_dir) if @mock_paths
  end

  def test_replaces_user_mention_with_display_name
    text = "<@U123ABC|john.doe>"
    result = @replacer.replace(text, @workspace)
    assert_equal "@john.doe", result
  end

  def test_keeps_raw_user_id_when_no_name
    text = "<@U123ABC>"
    result = @replacer.replace(text, @workspace)
    assert_equal "<@U123ABC>", result
  end

  def test_replaces_channel_mention_with_name
    text = "<#C123ABC|general>"
    result = @replacer.replace(text, @workspace)
    assert_equal "#general", result
  end

  def test_keeps_channel_id_when_no_name
    text = "<#C123ABC>"
    result = @replacer.replace(text, @workspace)
    assert_equal "#C123ABC", result
  end

  def test_replaces_links_with_label
    text = "<https://example.com|Example Site>"
    result = @replacer.replace(text, @workspace)
    assert_equal "Example Site", result
  end

  def test_replaces_links_without_label
    text = "<https://example.com/path>"
    result = @replacer.replace(text, @workspace)
    assert_equal "https://example.com/path", result
  end

  def test_replaces_here_mention
    text = "Hey <!here>, check this out"
    result = @replacer.replace(text, @workspace)
    assert_equal "Hey @here, check this out", result
  end

  def test_replaces_channel_mention_special
    text = "Attention <!channel>!"
    result = @replacer.replace(text, @workspace)
    assert_equal "Attention @channel!", result
  end

  def test_replaces_everyone_mention
    text = "<!everyone> please read"
    result = @replacer.replace(text, @workspace)
    assert_equal "@everyone please read", result
  end

  def test_handles_multiple_mentions
    text = "<@U123|alice> and <@U456|bob> joined <#C789|random>"
    result = @replacer.replace(text, @workspace)
    assert_equal "@alice and @bob joined #random", result
  end

  def test_handles_text_without_mentions
    text = "Just regular text with no mentions"
    result = @replacer.replace(text, @workspace)
    assert_equal text, result
  end

  def test_handles_empty_text
    result = @replacer.replace("", @workspace)
    assert_equal "", result
  end

  def test_uses_cached_user_name
    # Prime the cache
    @cache.set_user("test", "U999", "cached_user")

    text = "<@U999>"
    result = @replacer.replace(text, @workspace)
    assert_equal "@cached_user", result
  end

  def test_uses_cached_channel_name
    # Prime the cache
    @cache.set_channel("test", "cached_channel", "C999")

    text = "<#C999>"
    result = @replacer.replace(text, @workspace)
    assert_equal "#cached_channel", result
  end

  def test_user_regex_matches_u_prefix
    regex = SlackCli::Formatters::MentionReplacer::USER_MENTION_REGEX
    assert_match regex, "<@U12345>"
    assert_match regex, "<@U12345|name>"
  end

  def test_user_regex_matches_w_prefix
    regex = SlackCli::Formatters::MentionReplacer::USER_MENTION_REGEX
    assert_match regex, "<@W12345>"
    assert_match regex, "<@W12345|name>"
  end

  def test_channel_regex_matches_c_prefix
    regex = SlackCli::Formatters::MentionReplacer::CHANNEL_MENTION_REGEX
    assert_match regex, "<#C12345>"
    assert_match regex, "<#C12345|name>"
  end
end
