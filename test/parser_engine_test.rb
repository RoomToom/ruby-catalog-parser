# frozen_string_literal: true

require_relative 'test_helper'

class ParserEngineTest < LabTest
  def test_real_http_pagination_parallel_workers_and_downloaded_images
    start_fixture_server
    parser = SimpleWebsiteParser.new(@config)
    collection = parser.start_parse
    assert_equal 6, collection.count
    assert_equal 2, parser.stats[:pages]
    assert_equal 3, parser.stats[:worker_threads].size
    assert_operator @max_active, :>, 1
    assert_empty parser.errors
    assert_equal 1.25, collection.first.price
    assert_equal 'Seed', collection.first.category
    assert_includes collection.first.description, 'Pokémon'
    assert(collection.all? { |item| File.binread(File.join(@temporary, item.image_path)).start_with?("\x89PNG".b) })
  end

  def test_product_limit_and_partial_failure
    start_fixture_server(broken: true)
    @config['web_scraping']['max_products'] = 3
    parser = SimpleWebsiteParser.new(@config)
    assert_equal 2, parser.start_parse.count
    assert_equal 1, parser.errors.size
    assert_equal 1, parser.stats[:pages]
    refute parser.check_url_response("#{@config['web_scraping']['start_page']}missing")
  end

  def test_invalid_config_and_missing_fields
    @config['web_scraping']['threads'] = 0
    assert_raises(ArgumentError) { SimpleWebsiteParser.new(@config) }
    @config['web_scraping']['threads'] = 2
    parser = SimpleWebsiteParser.new(@config)
    doc = Nokogiri::HTML('<html></html>')
    assert_raises(RuntimeError) { parser.extract_product_price(doc) }
    assert_raises(RuntimeError) { parser.extract_product_name(doc) }
    assert_equal '', parser.extract_product_description(doc)
  end

  def test_complete_engine_saves_archive_with_only_current_results
    start_fixture_server
    engine = Engine.run(Configurator.new(@config).config, config: @config)
    assert_equal 6, engine.result[:count]
    assert File.file?(engine.archive_path)
    Zip::File.open(engine.archive_path) do |zip|
      names = zip.entries.map(&:name)
      assert_includes names, 'output/data.csv'
      assert_includes names, 'output/data.json'
      assert_includes names, 'output/data.txt'
      assert_includes names, 'db/local_database.sqlite'
      assert_includes names, 'output/run.json'
      assert_equal(6, names.count { |name| name.end_with?('.yaml') })
      assert_equal(6, names.count { |name| name.end_with?('.png') })
      refute(names.any? { |name| name.include?('archive.yaml') || name.end_with?('.zip') })
    end
    db = SQLite3::Database.new(File.join(@temporary, 'db/local_database.sqlite'))
    assert_equal 6, db.get_first_value('SELECT COUNT(*) FROM products')
    db.close
  end

  def test_actions_off_do_not_connect_to_unavailable_mongodb
    @config['database_config']['database_type'] = 'mongodb'
    @config['database_config']['mongodb_database']['uri'] = 'mongodb://127.0.0.1:1'
    engine = Engine.run(Configurator.new.config, config: @config)
    assert_equal 0, engine.result[:count]
    assert_empty engine.result[:databases]
  end

  def test_archive_rejects_files_outside_root
    assert_raises(ArgumentError) do
      ArchiveBuilder.create(@temporary, File.join(@temporary, 'archives'), [__FILE__])
    end
  end

  def test_save_without_parser_is_rejected
    assert_raises(ArgumentError) { Engine.run({ run_save_to_json: 1 }, config: @config) }
  end

  def test_database_is_closed_when_parser_fails
    start_fixture_server
    @config['web_scraping']['product_link_selector'] = '.missing-selector'
    connector = DatabaseConnector.new(@config)
    DatabaseConnector.stub(:new, connector) do
      assert_raises(RuntimeError) do
        Engine.run({ run_website_parser: 1, run_save_to_sqlite: 1 }, config: @config)
      end
    end
    assert_nil connector.db
  end

  def test_transient_http_error_is_retried_but_robots_block_is_respected
    start_fixture_server
    attempts = 0
    @server.mount_proc('/flaky') do |_request, response|
      attempts += 1
      response.status = attempts == 1 ? 503 : 200
      response.body = '<html>ok</html>'
    end
    @config['web_scraping']['retries'] = 1
    parser = SimpleWebsiteParser.new(@config)
    origin = URI(@config['web_scraping']['start_page'])
    assert parser.check_url_response("#{origin.scheme}://#{origin.host}:#{origin.port}/flaky")
    assert_equal 2, attempts
    refute parser.check_url_response("#{origin.scheme}://#{origin.host}:#{origin.port}/blocked/file")
  end
end
