# frozen_string_literal: true

module MyApplicationTokarchuk
  class Configurator
    KEYS = %i[run_website_parser run_save_to_file run_save_to_csv run_save_to_json run_save_to_yaml
              run_save_to_sqlite run_save_to_mongodb run_archive run_send_archive].freeze
    attr_reader :config

    def initialize(configuration = {})
      @config = KEYS.to_h { |key| [key, 0] }
      overrides = configuration['execution'] || configuration[:execution] || configuration
      configure(overrides)
    end

    def configure(overrides)
      overrides.each do |key, value|
        key = key.to_sym
        unless @config.key?(key)
          warn "Unknown configuration key: #{key}"
          next
        end
        raise ArgumentError, "#{key} must be 0 or 1" unless [0, 1].include?(value)

        @config[key] = value
      end
      self
    end

    def self.available_methods
      KEYS.dup
    end
  end
end
