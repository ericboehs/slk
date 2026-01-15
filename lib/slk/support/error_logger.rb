# frozen_string_literal: true

module Slk
  module Support
    # Logs errors to a file for debugging
    module ErrorLogger
      # Log an error to the error log file
      # @param error [Exception] The error to log
      # @param paths [XdgPaths] Path helper (for testing)
      # @return [String, nil] Path to the log file, or nil if logging failed
      def self.log(error, paths: XdgPaths.new)
        paths.ensure_cache_dir

        log_file = paths.cache_file('error.log')
        File.open(log_file, 'a') do |f|
          f.puts "#{Time.now.iso8601} - #{error.class}: #{error.message}"
          f.puts error.backtrace.first(10).map { |line| "  #{line}" }.join("\n") if error.backtrace
          f.puts
        end

        log_file
      rescue SystemCallError, IOError
        # If we can't write to the log, fail silently rather than crashing
        # The user will still see the error message in the console
        nil
      end
    end
  end
end
