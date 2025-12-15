# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
  t.verbose = true
end

desc "Run tests"
task default: :test

desc "Run the CLI"
task :run, [:args] do |_t, args|
  require_relative "lib/slack_cli"
  argv = args[:args]&.split(" ") || []
  SlackCli::CLI.new(argv).run
end

desc "Console with slack_cli loaded"
task :console do
  require_relative "lib/slack_cli"
  require "irb"
  IRB.start
end

desc "Check syntax of all Ruby files"
task :check do
  Dir.glob("lib/**/*.rb").each do |file|
    system("ruby", "-c", file) || exit(1)
  end
  puts "All files OK"
end

namespace :test do
  desc "Run model tests"
  Rake::TestTask.new(:models) do |t|
    t.libs << "test"
    t.libs << "lib"
    t.test_files = FileList["test/models/*_test.rb"]
  end

  desc "Run service tests"
  Rake::TestTask.new(:services) do |t|
    t.libs << "test"
    t.libs << "lib"
    t.test_files = FileList["test/services/*_test.rb"]
  end

  desc "Run command tests"
  Rake::TestTask.new(:commands) do |t|
    t.libs << "test"
    t.libs << "lib"
    t.test_files = FileList["test/commands/*_test.rb"]
  end
end
