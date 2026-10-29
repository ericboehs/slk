# frozen_string_literal: true

require 'test_helper'
require_relative '../../rakelib/release_check'

class ReleaseCheckTest < Minitest::Test
  CHANGELOG = <<~MD
    # Changelog

    ## [Unreleased]

    ## [0.2.0] - 2026-01-02

    ### Fixed

    - A fix.

    ## [0.1.0] - 2026-01-01

    - First.
  MD

  def test_changelog_section_is_the_body_without_the_heading
    assert_equal "### Fixed\n\n- A fix.\n", ReleaseCheck.changelog_section(CHANGELOG, '0.2.0')
  end

  def test_last_section_runs_to_the_end
    assert_equal "- First.\n", ReleaseCheck.changelog_section(CHANGELOG, '0.1.0')
  end

  def test_missing_or_empty_section_is_nil
    assert_nil ReleaseCheck.changelog_section(CHANGELOG, '0.3.0')
    assert_nil ReleaseCheck.changelog_section(CHANGELOG, 'Unreleased')
  end

  def test_version_prefix_does_not_match_a_longer_version
    changelog = "## [0.1.10] - x\n\n- Ten.\n"
    assert_nil ReleaseCheck.changelog_section(changelog, '0.1.1')
  end

  def test_unreleased_entries
    refute ReleaseCheck.unreleased_entries?(CHANGELOG)
    assert ReleaseCheck.unreleased_entries?(CHANGELOG.sub("## [Unreleased]\n", "## [Unreleased]\n\n- Pending.\n"))
  end

  def test_skipped_versions_are_older_tags_missing_from_rubygems
    skipped = ReleaseCheck.skipped_versions(
      tags: %w[v0.9.0 v0.10.0 v0.11.0 v0.12.0 v0.3.0 vnext], published: %w[0.9.0 0.11.0], version: '0.12.0'
    )
    assert_equal ['0.10.0'], skipped
  end

  def test_nothing_skipped_when_every_tag_is_published
    assert_empty ReleaseCheck.skipped_versions(tags: %w[v0.1.0], published: %w[0.1.0], version: '0.2.0')
  end
end
