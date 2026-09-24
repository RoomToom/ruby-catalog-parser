# frozen_string_literal: true

require 'bundler/setup'
require 'optparse'
require_relative '../libs/app_config_loader'

module MyApplicationTokarchuk
  module CLI
    def self.run(arguments = ARGV)
      AppConfigLoader.load_libs
      config = AppConfigLoader.config
      flags = {}
      option_parser(config, flags).parse!(arguments)
      raise OptionParser::InvalidArgument, arguments.join(' ') unless arguments.empty?

      if flags.delete(:show_config)
        AppConfigLoader.pretty_print_config_data(config)
        return 0
      end
      return 0 if flags.delete(:help)

      configurator = Configurator.new(config).configure(flags)
      engine = Engine.run(configurator.config, config: config)
      engine.result[:errors].empty? ? 0 : 2
    rescue StandardError => e
      warn "Помилка: #{e.class}: #{e.message}"
      warn 'Деталі: logs/error.log. Перевірте YAML, мережу та доступність вибраних сервісів.'
      1
    ensure
      LoggerManager.close if defined?(LoggerManager)
    end

    def self.option_parser(config, flags)
      OptionParser.new do |options|
        options.banner = 'Usage: bundle exec ruby main.rb [options]'
        options.on('--limit N', Integer, 'Maximum products') { |value| config['web_scraping']['max_products'] = value }
        options.on('--pages N', Integer, 'Maximum catalog pages') do |value|
          config['web_scraping']['max_pages'] = value
        end
        options.on('--threads N', Integer, 'Worker threads') { |value| config['web_scraping']['threads'] = value }
        options.on('--mongodb', 'Also save to MongoDB') { flags[:run_save_to_mongodb] = 1 }
        options.on('--no-sqlite', 'Disable SQLite export') { flags[:run_save_to_sqlite] = 0 }
        options.on('--no-archive', 'Disable ZIP') { flags[:run_archive] = 0 }
        options.on('--send-archive', 'Queue email using configured SMTP and Sidekiq') { flags[:run_send_archive] = 1 }
        options.on('--show-config', 'Print configuration and exit') { flags[:show_config] = true }
        options.on('-h', '--help', 'Show help') do
          puts options
          flags[:help] = true
        end
      end
    end
  end
end

exit MyApplicationTokarchuk::CLI.run if $PROGRAM_NAME == __FILE__
