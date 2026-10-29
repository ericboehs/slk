# frozen_string_literal: true

require 'json'
require 'net/http'

# Checks behind `rake release`. Kept free of Rake and shell calls so the
# rules can be tested.
module ReleaseCheck
  # Tagged before releases were checked, and never pushed to RubyGems.
  KNOWN_UNPUBLISHED = %w[0.3.0].freeze

  module_function

  # The body of `## [version]` in a Keep a Changelog file, without the
  # heading. nil when the section is missing or empty.
  def changelog_section(changelog, version)
    lines = changelog.lines
    start = lines.index { |line| line.start_with?("## [#{version}]") }
    return nil unless start

    rest = lines[(start + 1)..]
    stop = rest.index { |line| line.start_with?('## [') } || rest.size
    body = rest[0...stop].join.strip
    body.empty? ? nil : "#{body}\n"
  end

  # Entries still waiting under `## [Unreleased]`.
  def unreleased_entries?(changelog)
    !changelog_section(changelog, 'Unreleased').nil?
  end

  # Tagged versions older than `version` that never reached RubyGems.
  def skipped_versions(tags:, published:, version:)
    target = Gem::Version.new(version)
    tags.map { |tag| tag.delete_prefix('v') }
        .select { |tag| tag.match?(/\A\d+(\.\d+)*\z/) && Gem::Version.new(tag) < target }
        .reject { |tag| published.include?(tag) || KNOWN_UNPUBLISHED.include?(tag) }
        .sort_by { |tag| Gem::Version.new(tag) }
  end

  def published_versions(gem_name)
    uri = URI("https://rubygems.org/api/v1/versions/#{gem_name}.json")
    response = Net::HTTP.get_response(uri)
    return [] if response.is_a?(Net::HTTPNotFound)
    raise "RubyGems versions lookup failed: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).map { |entry| entry['number'] }
  end
end
