# frozen_string_literal: true

require 'yaml'
require 'erb'
require 'json'

module MyApplicationTokarchuk
  class AppConfigLoader
    ROOT = File.expand_path('..', __dir__)

    class << self
      attr_reader :loaded_files

      def config(default_file = File.join(ROOT, 'config/default_config.yaml'), directory = nil)
        data = load_default_config(default_file)
        directory ||= File.join(data.fetch('default').fetch('root_dir'), data['default'].fetch('yaml_dir'))
        data = deep_merge(data, load_config(directory))
        yield data if block_given?
        data
      end

      def pretty_print_config_data(data)
        puts JSON.pretty_generate(redact(data))
      end

      def load_libs(directory = __dir__)
        %w[date time logger fileutils csv digest pathname securerandom].each { |library| require library }
        @loaded_files ||= []
        Dir.glob(File.join(directory, '*.rb')).each do |file|
          next if @loaded_files.include?(file) || File.expand_path(file) == __FILE__

          relative = Pathname.new(file).relative_path_from(Pathname.new(__dir__)).to_s
          require_relative relative
          @loaded_files << file
        end
        @loaded_files
      end

      private

      def load_default_config(path)
        read_yaml(path)
      end

      def load_config(directory)
        raise ArgumentError, "Configuration directory not found: #{directory}" unless Dir.exist?(directory)

        Dir.glob(File.join(directory, '*.{yaml,yml}')).reduce({}) do |result, file|
          deep_merge(result, read_yaml(file))
        end
      end

      def read_yaml(path)
        template = ERB.new(File.read(path, encoding: 'UTF-8'))
        template.filename = File.expand_path(path)
        data = YAML.safe_load(template.result, permitted_classes: [], aliases: false) || {}
        raise ArgumentError, "Expected a YAML mapping: #{path}" unless data.is_a?(Hash)

        data
      end

      def deep_merge(left, right)
        left.merge(right) { |_key, old, new| old.is_a?(Hash) && new.is_a?(Hash) ? deep_merge(old, new) : new }
      end

      def redact(data)
        return data unless data.is_a?(Hash)

        data.to_h do |key, value|
          sensitive = key.to_s.match?(/password|secret|token|uri|redis_url/i)
          [key, sensitive ? '[REDACTED]' : redact(value)]
        end
      end
    end
  end
end
