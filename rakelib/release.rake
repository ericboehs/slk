# frozen_string_literal: true

# `rake release` in one step: check, build, tag, push git, push the gem,
# then create the GitHub release from the CHANGELOG.
#
# Bundler's gem_tasks supplies build, tag, and the git and gem pushes.
# This adds the checks before them and the GitHub release after. Each step
# skips work already done (tag exists, gem published, release exists), so a
# release that fails partway is finished by running it again.
#
# OTP: set GEM_HOST_OTP_CODE, or have the 1Password CLI installed; the code
# is read from the item named by RUBYGEMS_OTP_OP_ITEM (default "Rubygems")
# right before the push, so it is still fresh.

require 'English'
require_relative 'release_preflight'

helper = Bundler::GemHelper.instance
version = helper.gemspec.version.to_s
tag = "v#{version}"
preflight = ReleasePreflight.new(gem_name: helper.gemspec.name, version: version)

namespace :release do
  desc "Check that #{tag} is ready to release"
  task :preflight do
    problems = preflight.problems
    abort(problems.map { |problem| "✗ #{problem}" }.join("\n")) if problems.any?

    puts "#{tag}: ready#{' (already on RubyGems)' if preflight.published?}."
  end

  task :otp do
    next if ENV['GEM_HOST_OTP_CODE'] || preflight.published?
    next unless system('which', 'op', out: File::NULL)

    item = ENV.fetch('RUBYGEMS_OTP_OP_ITEM', 'Rubygems')
    code = IO.popen(['op', 'item', 'get', item, '--otp'], &:read).to_s.strip
    ENV['GEM_HOST_OTP_CODE'] = code unless code.empty?
  end

  desc "Create the GitHub release for #{tag} from CHANGELOG.md"
  task :github do
    exists = system('gh', 'release', 'view', tag, out: File::NULL, err: File::NULL)
    next puts("GitHub release #{tag} already exists.") if exists

    notes = ReleaseCheck.changelog_section(File.read('CHANGELOG.md'), version)
    IO.popen(['gh', 'release', 'create', tag, '--title', tag, '--verify-tag', '--notes-file', '-'], 'w') do |io|
      io.write(notes)
    end
    abort "gh release create #{tag} failed." unless $CHILD_STATUS.success?
  end
end

# Skip the push when this version is already published, so a re-run after a
# failed GitHub step does not fail on a duplicate push.
Rake::Task['release:rubygem_push'].tap do |push|
  actions = push.actions.dup
  push.clear_actions
  push.enhance(['release:otp']) do |task, args|
    next puts("#{helper.gemspec.name} #{version} is already on RubyGems.") if preflight.published?

    actions.each { |action| action.call(task, args) }
  end
end

Rake::Task['release'].tap do |release|
  release.clear_prerequisites
  release.enhance(%w[release:preflight build release:guard_clean release:source_control_push
                     release:rubygem_push release:github])
end
