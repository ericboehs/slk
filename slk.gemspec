# frozen_string_literal: true

require_relative "lib/slack_cli/version"

Gem::Specification.new do |spec|
  spec.name = "slk"
  spec.version = SlackCli::VERSION
  spec.authors = ["Eric Boehs"]
  spec.email = ["ericboehs@gmail.com"]

  spec.summary = "A command-line interface for Slack"
  spec.description = "Manage your Slack status, presence, DND, read messages, and more from the terminal. Pure Ruby, no dependencies."
  spec.homepage = "https://github.com/ericboehs/slack-cli"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ericboehs/slack-cli"
  spec.metadata["changelog_uri"] = "https://github.com/ericboehs/slack-cli/blob/main/CHANGELOG.md"

  # Specify which files should be added to the gem
  spec.files = Dir.chdir(__dir__) do
    Dir["{bin,lib}/**/*", "LICENSE", "README.md", "CHANGELOG.md"].reject do |f|
      File.directory?(f) || f.end_with?(".bash")
    end
  end

  spec.bindir = "bin"
  spec.executables = ["slk"]
  spec.require_paths = ["lib"]

  # No runtime dependencies - pure Ruby!
end
