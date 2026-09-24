# frozen_string_literal: true

require_relative 'app_config_loader'
require_relative 'configurator'
require_relative 'logger_manager'
require_relative 'simple_website_parser'
require_relative 'database_connector'
require_relative 'archive_builder'
require_relative 'archive_sender'

module MyApplicationTokarchuk
  class Engine
    ACTIONS = %i[run_website_parser run_save_to_file run_save_to_csv run_save_to_json run_save_to_yaml
                 run_save_to_sqlite run_save_to_mongodb].freeze
    attr_reader :config, :item_collection, :parser, :archive_path, :result

    def initialize(config = nil)
      @config = config
      @files = []
      @connectors = {}
      @item_collection = ItemCollection.new
    end

    def self.run(config_params, config: nil)
      new(config).run(config_params)
    end

    def load_config
      @config ||= AppConfigLoader.config
      puts 'Конфігурацію завантажено.'
      @config
    end

    def run(config_params)
      load_config
      initialize_logging
      params = Configurator.new(config_params).config
      validate_actions!(params)
      connect_databases(params)
      run_methods(params)
      close_databases
      write_manifest
      if params[:run_archive] == 1
        @archive_path = ArchiveBuilder.create(root, absolute(config['archive']['directory']),
                                              @files)
      end
      queue_archive if params[:run_send_archive] == 1
      puts "Зібрано товарів: #{item_collection.count}. Помилок сторінок: #{parser&.errors&.size || 0}."
      puts "ZIP: #{@archive_path}" if @archive_path
      self
    rescue StandardError => e
      LoggerManager.log_error("Engine failed: #{e.class}: #{e.message}")
      raise
    ensure
      close_databases
    end

    def run_methods(config_params)
      ACTIONS.each { |action| public_send(action) if config_params[action] == 1 }
    end

    def run_website_parser
      @parser = SimpleWebsiteParser.new(config)
      @item_collection = parser.start_parse
      @files.concat(item_collection.map(&:image_path).reject(&:empty?).map { |path| absolute(path) })
    end

    def run_save_to_file
      @files << item_collection.save_to_file(output('data.txt'))
    end

    def run_save_to_csv
      @files << item_collection.save_to_csv(output('data.csv'))
    end

    def run_save_to_json
      @files << item_collection.save_to_json(output('data.json'))
    end

    def run_save_to_yaml
      @files.concat(item_collection.save_to_yml(absolute(File.join(config['default']['yaml_dir'], 'products'))))
    end

    def run_save_to_sqlite
      connector = @connectors.fetch('sqlite')
      connector.save_items(item_collection)
      @files << connector.database_file
    end

    def run_save_to_mongodb
      connector = @connectors.fetch('mongodb')
      connector.save_items(item_collection)
      # Portable snapshot of persisted MongoDB records, included in the archive.
      path = output('mongodb_snapshot.json')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(connector.read_items), encoding: 'UTF-8')
      @files << path
    end

    private

    def root
      config.fetch('default').fetch('root_dir')
    end

    def absolute(path)
      File.expand_path(path, root)
    end

    def output(name)
      absolute(File.join(config['default']['output_dir'], name))
    end

    def initialize_logging
      LoggerManager.setup(config.fetch('logging'), root: root)
    end

    def validate_actions!(params)
      saving = ACTIONS.drop(1).any? { |key| params[key] == 1 }
      if saving && params[:run_website_parser] != 1
        raise ArgumentError,
              'Enable run_website_parser before saving products'
      end
      return unless params[:run_send_archive] == 1

      raise ArgumentError, 'Email requires run_archive: 1' unless params[:run_archive] == 1

      missing_address = %w[to from].any? { |key| config['mail'][key].to_s.empty? }
      raise ArgumentError, 'Set ARCHIVE_EMAIL and SMTP_FROM' if missing_address
    end

    def connect_databases(params)
      types = %w[sqlite mongodb].select { |type| params[:"run_save_to_#{type}"] == 1 }
      types.each do |type|
        db_config = config.merge('database_config' => config['database_config'].merge('database_type' => type))
        @connectors[type] = DatabaseConnector.new(db_config)
        @connectors[type].connect_to_database
      end
    end

    def close_databases
      @connectors.each_value(&:close_connection)
    end

    def write_manifest
      @result = { generated_at: Time.now.utc.iso8601, source: config['web_scraping']['start_page'],
                  count: item_collection.count, categories: item_collection.map(&:category).tally,
                  total_price: item_collection.total_price, currency: config['web_scraping']['currency'],
                  statistics: parser&.stats, errors: parser&.errors || [], databases: @connectors.keys }
      path = output('run.json')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.pretty_generate(@result), encoding: 'UTF-8')
      @files << path
    end

    def queue_archive
      ArchiveSender.configure_background(config)
      relative = Pathname.new(archive_path).relative_path_from(Pathname.new(root)).to_s.tr('\\', '/')
      jid = ArchiveSender.perform_async(relative, config['mail']['to'])
      LoggerManager.log_processed_file("Archive queued: #{jid}")
      puts "Архів у черзі Sidekiq: #{jid}. Доставка виконується worker-процесом."
    end
  end
end
