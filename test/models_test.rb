# frozen_string_literal: true

require_relative 'test_helper'

class ModelsTest < LabTest
  def test_item_defaults_blocks_dynamic_hash_and_alias
    item = Item.new(name: 'Pokémon') { |value| value.category = 'Seed' }
    assert_equal '', item.image_path
    assert_equal 0, item.price
    assert_equal 'Seed', item.category
    assert_equal Item.instance_method(:to_s), Item.instance_method(:info)
    item.instance_variable_set(:@custom_field, 'dynamic')
    assert_equal 'dynamic', item.to_h[:custom_field]
    assert_includes item.inspect, 'Pokémon'
    item.remove_instance_variable(:@custom_field)
    item.update { |value| value.price = 20 }
    assert_equal 20, item.price
  end

  def test_item_validation_and_update_rollback
    assert_raises(ArgumentError) { Item.new(price: -1) }
    assert_raises(ArgumentError) { Item.new(name: '') }
    assert_raises(ArgumentError) { Item.new(price: Float::NAN) }
    assert_raises(ArgumentError) { Item.new(unknown: 1) }
    item = product
    assert_raises(ArgumentError) { item.update { |value| value.price = -1 } }
    assert_equal 63, item.price
  end

  def test_comparison_faker_and_collection_operations
    before = ItemCollection.object_count
    collection = ItemCollection.new
    first = product(price: 1)
    second = product(name: 'Ivysaur', price: 1)
    collection.add_item(first)
    collection.add_item(second)
    assert_equal before + 1, ItemCollection.object_count
    assert_equal '1.0.0', ItemCollection.class_info[:version]
    assert_equal 2, collection.total_price
    assert_equal %w[Bulbasaur Ivysaur], collection.names
    assert_equal 2, collection.in_category('Seed').size
    assert collection.respond_to?(:show_all_items)
    assert_output(/Bulbasaur/) { collection.show_all_items }
    assert_raises(NoMethodError) { collection.not_a_method }
    collection.remove_item(first)
    assert_same second, collection.first
    collection.delete_items
    assert_empty collection
  end

  def test_fake_items_and_sorting
    collection = ItemCollection.new
    collection.generate_test_items(3)
    assert_equal 3, collection.count
    assert collection.all?(Item)
    assert_equal collection.map(&:price).sort, collection.sorted_by_price.map(&:price)
  end

  def test_concurrent_additions_and_snapshot
    collection = ItemCollection.new
    threads = Array.new(4) { Thread.new { 25.times { collection.add_item(product) } } }
    threads.each(&:value)
    assert_equal 100, collection.count
    collection.items.clear
    assert_equal 100, collection.count
  end

  def test_all_export_formats_and_separate_yaml_files
    collection = ItemCollection.new
    collection.add_item(product(name: 'Бульбазавр', price: 1.25))
    collection.add_item(product(name: '=formula', price: 2.75, url: 'https://example.test/2'))
    json = collection.save_to_json(File.join(@temporary, 'out/data.json'))
    csv = collection.save_to_csv(File.join(@temporary, 'out/data.csv'))
    txt = collection.save_to_file(File.join(@temporary, 'out/data.txt'))
    yaml = collection.save_to_yml(File.join(@temporary, 'products'))
    assert_equal 2, JSON.parse(File.read(json)).size
    rows = CSV.read(csv, headers: true)
    assert_equal 'Бульбазавр', rows[0]['name']
    assert_equal "'=formula", rows[1]['name']
    assert_includes File.read(txt), 'Бульбазавр'
    assert_equal 2, yaml.size
    assert(yaml.all? { |path| YAML.safe_load_file(path)['categories'][0]['products'].size == 1 })
    assert_equal '_CON', ItemCollection.safe_name('CON')
    refute_includes ItemCollection.safe_name('../../x'), '/'
  end

  def test_configurator_defaults_overrides_and_unknown_key
    configurator = Configurator.new
    assert configurator.config.values.all?(&:zero?)
    configurator.configure(run_website_parser: 1)
    assert_equal 1, configurator.config[:run_website_parser]
    assert_output('', /Unknown configuration key/) { configurator.configure(invalid: 1) }
    assert_raises(ArgumentError) { configurator.configure(run_website_parser: 'yes') }
    assert_includes Configurator.available_methods, :run_save_to_mongodb
  end
end
