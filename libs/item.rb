# frozen_string_literal: true

require 'faker'
require 'bigdecimal'
require_relative 'logger_manager'

module MyApplicationTokarchuk
  class Item
    include Comparable

    DEFAULTS = {
      name: 'Unnamed product', price: 0.0, description: '', category: 'Uncategorized', image_path: '',
      source_url: '', sku: '', currency: 'GBP'
    }.freeze
    attr_accessor(*DEFAULTS.keys)

    def initialize(attributes = {})
      unknown = attributes.keys.map(&:to_sym) - DEFAULTS.keys
      raise ArgumentError, "Unknown Item attributes: #{unknown.join(', ')}" unless unknown.empty?

      DEFAULTS.merge(attributes.transform_keys(&:to_sym)).each { |key, value| public_send("#{key}=", value) }
      yield self if block_given?
      validate!
      LoggerManager.log_processed_file("Item initialized: #{name}")
    end

    def to_h
      instance_variables.to_h { |variable| [variable.to_s.delete_prefix('@').to_sym, instance_variable_get(variable)] }
    end

    def to_s
      to_h.map { |key, value| "#{key}: #{value}" }.join(', ')
    rescue StandardError => e
      LoggerManager.log_error("Item#info: #{e.class}: #{e.message}")
      raise
    end
    alias_method :info, :to_s

    def inspect
      "#<#{self.class.name} #{self}>"
    end

    def update
      previous = to_h
      yield self
      validate!
      LoggerManager.log_processed_file("Item updated: #{name}")
      self
    rescue StandardError
      previous.each { |key, value| public_send("#{key}=", value) }
      raise
    end

    def <=>(other)
      price <=> other.price if other.is_a?(Item)
    end

    def self.generate_fake
      new(name: Faker::Commerce.product_name, price: Faker::Commerce.price,
          description: Faker::Lorem.paragraph, category: Faker::Commerce.department(max: 1),
          sku: Faker::Number.unique.number(digits: 8).to_s)
    end

    private

    def validate!
      self.price = Float(price)
      raise ArgumentError, 'Price must be finite and non-negative' unless price.finite? && price >= 0
      raise ArgumentError, 'Name must not be empty' if name.to_s.strip.empty?
    end
  end
end
