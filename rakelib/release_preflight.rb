# frozen_string_literal: true

require_relative 'release_check'

# The checks `rake release:preflight` runs before anything is built or
# tagged. Each failure is a message; nothing is changed.
class ReleasePreflight
  def initialize(gem_name:, version:)
    @gem_name = gem_name
    @version = version
  end

  def published
    @published ||= ReleaseCheck.published_versions(@gem_name)
  end

  def published?
    published.include?(@version)
  end

  # @return [Array<String>] problems; empty means ready
  def problems
    system('git', 'fetch', '--quiet', 'origin', 'master', '--tags')
    [branch_problem, behind_problem, *changelog_problems, skipped_problem, gh_problem].compact
  end

  private

  def branch_problem
    branch = capture('git', 'branch', '--show-current')
    "Release from master, not #{branch}." unless branch == 'master'
  end

  def behind_problem
    behind = capture('git', 'rev-list', '--count', 'HEAD..origin/master')
    "master is #{behind} commit(s) behind origin/master; pull first." unless behind == '0'
  end

  def changelog_problems
    changelog = File.read('CHANGELOG.md')
    missing = ReleaseCheck.changelog_section(changelog, @version).nil?
    pending = ReleaseCheck.unreleased_entries?(changelog)
    [
      ("CHANGELOG.md has no entries under ## [#{@version}]." if missing),
      ('CHANGELOG.md still has entries under ## [Unreleased]; move them first.' if pending)
    ]
  end

  def skipped_problem
    tags = capture('git', 'tag', '-l', 'v*').split
    skipped = ReleaseCheck.skipped_versions(tags: tags, published: published, version: @version)
    "Tagged but never pushed to RubyGems: #{skipped.join(', ')}. Publish them first." if skipped.any?
  end

  def gh_problem
    'gh is not signed in; run `gh auth login`.' unless system('gh', 'auth', 'status', out: File::NULL, err: File::NULL)
  end

  def capture(*cmd)
    IO.popen(cmd, err: File::NULL, &:read).to_s.strip
  end
end
