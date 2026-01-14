# frozen_string_literal: true

require_relative "lib/slack_cli/version"

Gem::Specification.new do |spec|
  spec.name = "slk"
  spec.version = SlackCli::VERSION
  spec.authors = ["Eric Boehs"]
  spec.email = ["ericboehs@gmail.com"]

  spec.summary = "A command-line interface for Slack"
  spec.description = "Manage your Slack status, presence, DND, read messages, and more from the terminal. Pure Ruby, no dependencies."
  spec.homepage = "https://github.com/ericboehs/slk"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/ericboehs/slk"
  spec.metadata["changelog_uri"] = "https://github.com/ericboehs/slk/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem
  spec.files = Dir.chdir(__dir__) do
    Dir["{bin,lib}/**/*", "LICENSE", "README.md", "CHANGELOG.md"].reject do |f|
      File.directory?(f) || f.end_with?(".bash")
    end
  end

  spec.bindir = "bin"
  spec.executables = ["slk"]
  spec.require_paths = ["lib"]

  spec.post_install_message = <<~MSG
    slk 0.2.0: Config directory changed from slack-cli to slk

    If upgrading from 0.1.x, migrate your config:
      mv ${XDG_CONFIG_HOME:-~/.config}/slack-cli ${XDG_CONFIG_HOME:-~/.config}/slk
      mv ${XDG_CACHE_HOME:-~/.cache}/slack-cli ${XDG_CACHE_HOME:-~/.cache}/slk
  MSG

  # No runtime dependencies - pure Ruby!
end
