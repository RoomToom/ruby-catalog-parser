# frozen_string_literal: true

require 'json'
require 'csv'
require 'yaml'
require 'digest'
require 'fileutils'
require_relative 'item_container'

module MyApplicationTokarchuk
  class ItemCollection
    include ItemContainer
    include Enumerable

    def initialize
      @items = []
      @mutex = Mutex.new
      self.class.register_object
    end

    def items
      @mutex.synchronize { @items.dup }
    end

    def empty?
      @mutex.synchronize { @items.empty? }
    end

    def each(&block)
      return enum_for(:each) unless block

      items.each(&block)
    end

    def generate_test_items(count = 5)
      Integer(count).times { add_item(Item.generate_fake) }
      self
    end

    def names
      map(&:name)
    end

    def in_category(category)
      select { |item| item.category == category }
    end

    def total_price
      reduce(BigDecimal('0')) { |sum, item| sum + BigDecimal(item.price.to_s) }.to_f
    end

    def sorted_by_price
      sort
    end

    def save_to_file(path)
      write(path, "#{map(&:info).join("\n")}\n")
    end

    def save_to_json(path)
      write(path, JSON.pretty_generate(map(&:to_h)))
    end

    def save_to_csv(path)
      content = CSV.generate do |csv|
        csv << Item::DEFAULTS.keys
        each do |item|
          csv << Item::DEFAULTS.keys.map { |key| csv_value(item.to_h.fetch(key)) }
        end
      end
      write(path, content)
    end

    def save_to_yml(directory)
      map do |item|
        path = File.join(directory, self.class.safe_name(item.category), "#{self.class.item_filename(item)}.yaml")
        product = item.to_h.transform_keys(&:to_s).merge('media' => item.image_path)
        data = { 'categories' => [{ 'name' => item.category, 'products' => [product] }] }
        write(path, YAML.dump(data))
      end
    end

    def self.safe_name(value)
      slug = value.to_s.unicode_normalize(:nfkc).gsub(/[^\p{L}\p{N}_-]+/, '_').gsub(/\A_+|_+\z/, '')[0, 70]
      slug = 'unnamed' if slug.empty?
      slug = "_#{slug}" if slug.match?(/\A(?:con|prn|aux|nul|com[1-9]|lpt[1-9])\z/i)
      slug
    end

    def self.item_filename(item)
      identity = item.source_url.empty? ? "#{item.name}:#{item.sku}" : item.source_url
      "#{safe_name(item.name)}-#{Digest::SHA256.hexdigest(identity)[0, 10]}"
    end

    private

    def write(path, content)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content, encoding: 'UTF-8')
      LoggerManager.log_processed_file("Saved: #{path}")
      File.expand_path(path)
    end

    def csv_value(value)
      value.is_a?(String) && value.match?(/\A[=+@\-\t\r]/) ? "'#{value}" : value
    end
  end
end
