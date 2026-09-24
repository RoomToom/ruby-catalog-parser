# frozen_string_literal: true

require_relative 'test_helper'

class ConfigDatabaseTest < LabTest
  def test_config_loading_erb_block_and_no_product_yaml_merge
    config = AppConfigLoader.config { |data| data['test_block'] = true }
    assert config['test_block']
    assert_equal 'sqlite', config.dig('database_config', 'database_type')
    assert_equal AppConfigLoader::ROOT, config.dig('default', 'root_dir')
    assert_equal 1, config.dig('execution', 'run_website_parser')
    assert_operator config.size, :>=, 7
    initial = AppConfigLoader.load_libs.dup
    assert_equal initial, AppConfigLoader.load_libs
    output, = capture_io { AppConfigLoader.pretty_print_config_data(config) }
    assert_equal '[REDACTED]', JSON.parse(output).dig('mail', 'smtp_password')
  end

  def test_invalid_yaml_is_rejected
    path = File.join(@temporary, 'bad.yaml')
    File.write(path, "--- !ruby/object:Object {}\n")
    assert_raises(Psych::DisallowedClass) { AppConfigLoader.config(path) }
  end

  def test_logger_writes_separate_error_file
    LoggerManager.log_processed_file('parsed file')
    LoggerManager.log_error('expected test error')
    LoggerManager.close
    assert_includes File.read(File.join(@temporary, 'logs/application.log')), 'parsed file'
    errors = File.read(File.join(@temporary, 'logs/error.log'))
    assert_includes errors, 'expected test error'
    refute_includes errors, 'parsed file'
  end

  def test_sqlite_real_roundtrip_upsert_and_close
    connector = DatabaseConnector.new(@config)
    connector.connect_to_database
    collection = ItemCollection.new
    item = product(name: "Pokemon ' quote")
    collection.add_item(item)
    connector.save_items(collection)
    item.update { |value| value.price = 12.5 }
    connector.save_items(collection)
    assert_equal 1, connector.read_items.size
    assert_equal 12.5, connector.read_items.first['price']
    assert_equal "Pokemon ' quote", connector.read_items.first['name']
    connector.close_connection
    assert_nil connector.db
    connector.connect_to_database
    assert_equal 1, connector.read_items.size
  ensure
    connector&.close_connection
  end

  def test_sqlite_rolls_back_batch_on_invalid_item
    connector = DatabaseConnector.new(@config)
    connector.connect_to_database
    collection = ItemCollection.new
    collection.add_item(product)
    collection.add_item(Item.new)
    assert_raises(ArgumentError) { connector.save_items(collection) }
    assert_empty connector.read_items
  ensure
    connector&.close_connection
  end

  def test_unsupported_database
    @config['database_config']['database_type'] = 'unknown'
    connector = DatabaseConnector.new(@config)
    assert_raises(ArgumentError) { connector.connect_to_database }
    assert_nil connector.db
  end

  def test_mongodb_real_roundtrip_if_service_is_requested
    skip 'Set TEST_MONGODB_URI to enable the real MongoDB integration test' unless ENV['TEST_MONGODB_URI']

    @config['database_config']['database_type'] = 'mongodb'
    @config['database_config']['mongodb_database'].merge!('uri' => ENV.fetch('TEST_MONGODB_URI', nil),
                                                          'db_name' => "tokarchuk_test_#{Process.pid}")
    connector = DatabaseConnector.new(@config)
    connector.connect_to_database
    collection = ItemCollection.new
    item = product
    collection.add_item(item)
    connector.save_items(collection)
    item.price = 19.5
    connector.save_items(collection)
    assert_equal 1, connector.read_items.size
    assert_equal 19.5, connector.read_items.first['price']
    connector.close_connection
    assert_nil connector.db
    connector.connect_to_database
    assert_equal 1, connector.read_items.size
  ensure
    database = connector&.db
    database&.database&.drop
    connector&.close_connection
  end
end
