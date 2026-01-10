# frozen_string_literal: true

module SlackCli
  module Support
    module ErrorLogger
      def self.log(error, paths: XdgPaths.new)
        paths.ensure_cache_dir

        log_file = paths.cache_file('error.log')
        File.open(log_file, 'a') do |f|
          f.puts "#{Time.now.iso8601} - #{error.class}: #{error.message}"
          f.puts error.backtrace.first(10).map { |line| "  #{line}" }.join("\n") if error.backtrace
          f.puts
        end
      end
    end
  end
end
