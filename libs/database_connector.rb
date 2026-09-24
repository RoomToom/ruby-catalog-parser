# frozen_string_literal: true

require 'sqlite3'
require 'mongo'
require 'fileutils'
require_relative 'item'

module MyApplicationTokarchuk
  class DatabaseConnector
    attr_reader :db, :type, :database_file

    def initialize(config)
      @config = config.fetch('database_config')
      @root = config.fetch('default').fetch('root_dir')
      @type = @config.fetch('database_type')
      @db = nil
    end

    def connect_to_database
      return db if db

      case type
      when 'sqlite' then connect_to_sqlite
      when 'mongodb' then connect_to_mongodb
      else raise ArgumentError, "Unsupported database type: #{type}"
      end
      LoggerManager.log_processed_file("Connected to #{type}")
      db
    rescue StandardError => e
      LoggerManager.log_error("Database connection failed (#{type}): #{e.class}")
      close_connection
      raise
    end

    def close_connection
      @db&.close
      @db = nil
    end

    def save_items(collection)
      raise 'Database is not connected' unless db

      type == 'sqlite' ? save_sqlite(collection) : save_mongodb(collection)
      LoggerManager.log_processed_file("Saved #{collection.count} products to #{type}")
      collection.count
    end

    def read_items
      if type == 'sqlite'
        db.execute('SELECT * FROM products ORDER BY source_url')
      else
        mongo_collection.find.sort(source_url: 1).map { |row| row.except('_id') }
      end
    end

    private

    def connect_to_sqlite
      settings = @config.fetch('sqlite_database')
      @database_file = File.expand_path(settings.fetch('db_file'), @root)
      FileUtils.mkdir_p(File.dirname(@database_file))
      @db = SQLite3::Database.new(@database_file)
      db.busy_timeout = settings.fetch('timeout', 5000)
      db.results_as_hash = true
      db.execute('PRAGMA foreign_keys = ON')
      db.execute(<<~SQL)
        CREATE TABLE IF NOT EXISTS products (
          source_url TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL,
          price REAL NOT NULL CHECK(price >= 0), description TEXT NOT NULL,
          category TEXT NOT NULL, image_path TEXT NOT NULL, sku TEXT NOT NULL,
          currency TEXT NOT NULL, updated_at TEXT NOT NULL
        )
      SQL
    end

    def connect_to_mongodb
      settings = @config.fetch('mongodb_database')
      @db = Mongo::Client.new(settings.fetch('uri'), database: settings.fetch('db_name'),
                                                     server_selection_timeout: settings.fetch('timeout', 5))
      db.database.command(ping: 1)
      mongo_collection.indexes.create_one({ source_url: 1 }, unique: true)
    end

    def mongo_collection
      db[@config.fetch('mongodb_database').fetch('collection', 'products')]
    end

    def row_for(item)
      raise ArgumentError, 'Database products need a source_url' if item.source_url.to_s.empty?

      item.to_h.merge(updated_at: Time.now.utc.iso8601)
    end

    def save_sqlite(collection)
      fields = (Item::DEFAULTS.keys + [:updated_at]).freeze
      updates = (fields - [:source_url]).map { |field| "#{field}=excluded.#{field}" }.join(',')
      sql = "INSERT INTO products (#{fields.join(',')}) VALUES (#{(['?'] * fields.size).join(',')}) " \
            "ON CONFLICT(source_url) DO UPDATE SET #{updates}"
      db.transaction do
        collection.each do |item|
          row = row_for(item)
          db.execute(sql, fields.map { |field| row.fetch(field) })
        end
      end
    end

    def save_mongodb(collection)
      collection.each do |item|
        row = row_for(item)
        mongo_collection.update_one({ source_url: item.source_url }, { '$set' => row }, upsert: true)
      end
    end
  end
end
