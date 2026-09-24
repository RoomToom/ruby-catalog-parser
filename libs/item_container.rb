# frozen_string_literal: true

require_relative 'item'

module MyApplicationTokarchuk
  module ItemContainer
    def self.included(class_instance)
      class_instance.extend(ClassMethods)
      class_instance.include(InstanceMethods)
    end

    module ClassMethods
      def class_info
        { name: name, version: '1.0.0' }
      end

      def object_count
        @object_count || 0
      end

      def register_object
        @object_count = object_count + 1
      end
    end

    module InstanceMethods
      def add_item(item)
        raise ArgumentError, 'Expected Item' unless item.is_a?(Item)

        @mutex.synchronize { @items << item }
        LoggerManager.log_processed_file("Collection add: #{item.name}")
        item
      end

      def remove_item(item)
        # Comparable compares by price, so removal must use object identity.
        removed = @mutex.synchronize do
          index = @items.index { |entry| entry.equal?(item) }
          @items.delete_at(index) if index
        end
        LoggerManager.log_processed_file("Collection remove: #{item.name}") if removed
        removed
      end

      def delete_items
        @mutex.synchronize { @items.clear }
        LoggerManager.log_processed_file('Collection cleared')
      end

      def method_missing(method, *arguments, &)
        return super unless method == :show_all_items && arguments.empty?

        each { |item| puts item.info }
      end

      def respond_to_missing?(method, include_private = false)
        method == :show_all_items || super
      end
    end
  end
end
