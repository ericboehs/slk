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

  # API Fallback Tests

  def test_api_lookup_for_user_without_cache
    mock_api = MockApiClient.new
    mock_api.stub("users.info", {
      "ok" => true,
      "user" => {
        "id" => "U777",
        "name" => "john.doe",
        "profile" => {
          "display_name" => "John Doe",
          "real_name" => "John D"
        }
      }
    })

    replacer = SlackCli::Formatters::MentionReplacer.new(
      cache_store: @cache,
      api_client: mock_api
    )

    text = "<@U777>"
    result = replacer.replace(text, @workspace)
    assert_equal "@John Doe", result

    # Verify it was cached
    assert_equal "John Doe", @cache.get_user("test", "U777")
  end

  def test_api_lookup_fallback_to_real_name
    mock_api = MockApiClient.new
    mock_api.stub("users.info", {
      "ok" => true,
      "user" => {
        "id" => "U888",
        "name" => "jane.doe",
        "profile" => {
          "display_name" => "",
          "real_name" => "Jane Doe"
        }
      }
    })

    replacer = SlackCli::Formatters::MentionReplacer.new(
      cache_store: @cache,
      api_client: mock_api
    )

    text = "<@U888>"
    result = replacer.replace(text, @workspace)
    assert_equal "@Jane Doe", result
  end

  def test_api_error_falls_back_gracefully
    api_client = Object.new
    api_client.define_singleton_method(:post) do |_workspace, _method, _params = {}|
      raise SlackCli::ApiError, "user_not_found"
    end
    api_client.define_singleton_method(:post_form) do |_workspace, _method, _params = {}|
      raise SlackCli::ApiError, "user_not_found"
    end

    replacer = SlackCli::Formatters::MentionReplacer.new(
      cache_store: @cache,
      api_client: api_client
    )

    text = "<@UNOTFOUND>"
    result = replacer.replace(text, @workspace)
    # Should fall back to showing raw ID
    assert_equal "<@UNOTFOUND>", result
  end

  def test_api_lookup_for_channel_without_cache
    mock_api = MockApiClient.new
    mock_api.stub("conversations.info", {
      "ok" => true,
      "channel" => {
        "id" => "C888",
        "name" => "engineering"
      }
    })

    replacer = SlackCli::Formatters::MentionReplacer.new(
      cache_store: @cache,
      api_client: mock_api
    )

    text = "<#C888>"
    result = replacer.replace(text, @workspace)
    assert_equal "#engineering", result

    # Verify it was cached
    assert_equal "engineering", @cache.get_channel_name("test", "C888")
  end

  def test_channel_api_error_falls_back_gracefully
    api_client = Object.new
    api_client.define_singleton_method(:get) do |_workspace, _method, _params = {}|
      raise SlackCli::ApiError, "channel_not_found"
    end
    api_client.define_singleton_method(:post_form) do |_workspace, _method, _params = {}|
      raise SlackCli::ApiError, "channel_not_found"
    end

    replacer = SlackCli::Formatters::MentionReplacer.new(
      cache_store: @cache,
      api_client: api_client
    )

    text = "<#CNOTFOUND>"
    result = replacer.replace(text, @workspace)
    # Should fall back to showing just the ID
    assert_equal "#CNOTFOUND", result
  end

  def test_no_api_client_returns_raw_id
    # Replacer without API client
    replacer = SlackCli::Formatters::MentionReplacer.new(
      cache_store: @cache,
      api_client: nil
    )

    text = "<@UNOAPI>"
    result = replacer.replace(text, @workspace)
    assert_equal "<@UNOAPI>", result
  end
end
