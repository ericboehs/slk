# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

group :development, :test do
  gem 'bigdecimal' # Needed for Ruby 4.0+ (removed from stdlib)
  gem 'minitest', '~> 5.0'
  gem 'parallel', '< 2.0' # 2.0+ requires Ruby 3.3; we still support 3.2
  gem 'rake', '~> 13.0'
  gem 'rubocop', require: false
  gem 'simplecov', '~> 0.22', require: false
end
