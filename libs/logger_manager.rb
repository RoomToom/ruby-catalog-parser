# frozen_string_literal: true

require 'logger'
require 'fileutils'

module MyApplicationTokarchuk
  class LoggerManager
    class << self
      attr_reader :logger, :error_logger

      def setup(config, root: Dir.pwd)
        close
        directory = File.expand_path(config.fetch('directory', 'logs'), root)
        FileUtils.mkdir_p(directory)
        level = Logger::Severity.const_get(config.fetch('level', 'INFO').upcase, false)
        files = config.fetch('files')
        @logger = Logger.new(File.join(directory, files.fetch('application_log')), 3, 1_048_576)
        @error_logger = Logger.new(File.join(directory, files.fetch('error_log')), 3, 1_048_576)
        [@logger, @error_logger].each { |log| log.level = level }
        @logger
      end

      def log_processed_file(message)
        @logger&.info(message)
      end

      def log_error(message)
        @logger&.error(message)
        @error_logger&.error(message)
      end

      def close
        @logger&.close
        @error_logger&.close
        @logger = @error_logger = nil
      end
    end
  end
end
