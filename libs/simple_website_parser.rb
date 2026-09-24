# frozen_string_literal: true

require 'mechanize'
require 'uri'
require_relative 'item_collection'

module MyApplicationTokarchuk
  class SimpleWebsiteParser
    attr_reader :config, :agent, :item_collection, :errors, :stats

    def initialize(config)
      @config = config.fetch('web_scraping')
      @root = config.fetch('default').fetch('root_dir')
      @media_dir = File.expand_path(config.fetch('default').fetch('media_dir'), @root)
      @origin = URI.parse(@config.fetch('start_page'))
      @item_collection = ItemCollection.new
      @errors = []
      @stats = { pages: 0, attempted: 0, collected: 0, failed: 0, worker_threads: [] }
      @rate_mutex = Mutex.new
      @stats_mutex = Mutex.new
      @next_request = 0.0
      validate_config!
      @agent = build_agent
    end

    def start_parse
      links = discover_links
      raise 'No product links found; check the configured selectors' if links.empty?

      queue = Queue.new
      links.each { |link| queue << link }
      workers = Array.new([config.fetch('threads'), links.size].min) do
        Thread.new do
          local_agent = build_agent
          loop do
            link = queue.pop(true)
            process_product(link, local_agent)
          rescue ThreadError
            break
          end
        end
      end
      workers.each(&:value)
      @stats[:collected] = item_collection.count
      @stats[:failed] = errors.size
      raise "All #{links.size} product pages failed; see error.log" if item_collection.none?

      # Stable export order even when HTTP requests complete in a different order.
      sorted = item_collection.items.sort_by(&:source_url)
      item_collection.delete_items
      sorted.each { |item| item_collection.add_item(item) }
      item_collection
    end

    def extract_products_links(page)
      page.css(config.fetch('product_link_selector', config.fetch('product_name_selector'))).filter_map do |node|
        href = node['href'] || node.at_css('a')&.[]('href') || node.ancestors('a').first&.[]('href')
        canonical_url(href, page.uri.to_s) if href
      end.uniq
    end

    def parse_product_page(product_link, local_agent = agent)
      page = fetch(local_agent, product_link)
      categories = page.css(config.fetch('product_category_selector')).map { |node| node.text.strip }
      category = categories.reject { |value| value.casecmp?('Pokemon') }.last || categories.first || 'Uncategorized'
      item = Item.new(name: extract_product_name(page), price: extract_product_price(page),
                      description: extract_product_description(page), category: category,
                      source_url: product_link, sku: page.at_css(config.fetch('product_sku_selector'))&.text.to_s.strip,
                      currency: config.fetch('currency'))
      image_url = extract_product_image(page)
      item.image_path = download_image(item, image_url, local_agent) if image_url
      item
    end

    def extract_product_name(product)
      text = product.at_css(config.fetch('product_name_selector'))&.text.to_s.strip
      raise 'Product name is missing' if text.empty?

      text
    end

    def extract_product_price(product)
      text = product.at_css(config.fetch('product_price_selector'))&.text.to_s
      normalized = text.gsub(/[^\d.,]/, '').delete(',')
      raise "Missing or invalid product price: #{text.inspect}" unless normalized.match?(/\A\d+(?:\.\d{1,2})?\z/)

      BigDecimal(normalized).to_f
    end

    def extract_product_description(product)
      product.at_css(config.fetch('product_description_selector'))&.text.to_s.strip.gsub(/\s+/, ' ')
    end

    def extract_product_image(product)
      node = product.at_css(config.fetch('product_image_selector'))
      href = node&.[]('href') || node&.[]('src')
      canonical_url(href, product.uri.to_s) if href
    end

    def check_url_response(url)
      fetch(agent, url).code == '200'
    rescue StandardError => e
      LoggerManager.log_error("URL unavailable: #{url} (#{e.class})")
      false
    end

    private

    def validate_config!
      %w[max_pages max_products threads timeout].each do |key|
        unless config[key].is_a?(Integer) && config[key].positive?
          raise ArgumentError,
                "#{key} must be a positive integer"
        end
      end
      raise ArgumentError, 'threads must be <= 16' if config['threads'] > 16
      raise ArgumentError, 'request_interval must be non-negative' if Float(config.fetch('request_interval')).negative?
      raise ArgumentError, 'retries must be between 0 and 5' unless (0..5).cover?(config.fetch('retries'))
      raise ArgumentError, 'Use an HTTP(S) start_page' unless %w[http https].include?(@origin.scheme)
    end

    def build_agent
      Mechanize.new do |client|
        client.user_agent = config.fetch('user_agent')
        client.open_timeout = config.fetch('timeout')
        client.read_timeout = config.fetch('timeout')
        client.robots = true
        client.max_history = 0
      end
    end

    def discover_links
      links = []
      visited = []
      url = canonical_url(config.fetch('start_page'))
      while url && visited.size < config.fetch('max_pages') && links.size < config.fetch('max_products')
        break if visited.include?(url)

        page = fetch(agent, url)
        visited << url
        links |= extract_products_links(page)
        @stats[:pages] += 1
        next_href = page.at_css(config.fetch('next_page_selector'))&.[]('href')
        url = next_href && canonical_url(next_href, page.uri.to_s)
      end
      links.first(config.fetch('max_products'))
    end

    def process_product(link, local_agent)
      @stats_mutex.synchronize do
        @stats[:attempted] += 1
        @stats[:worker_threads] |= [Thread.current.object_id]
      end
      item_collection.add_item(parse_product_page(link, local_agent))
    rescue StandardError => e
      @stats_mutex.synchronize { @errors << { url: link, error: "#{e.class}: #{e.message}" } }
      LoggerManager.log_error("Product failed: #{link}: #{e.class}: #{e.message}")
    end

    def canonical_url(value, base = @origin.to_s)
      uri = URI.join(base, value)
      unless %w[http https].include?(uri.scheme) && uri.host == @origin.host && uri.port == @origin.port
        raise ArgumentError, "URL is outside the configured site: #{uri}"
      end
      raise ArgumentError, 'Cart actions must not be requested' if uri.query.to_s.include?('add-to-cart')

      uri.fragment = nil
      uri.to_s
    end

    def throttle
      @rate_mutex.synchronize do
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        sleep(@next_request - now) if @next_request > now
        @next_request = Process.clock_gettime(Process::CLOCK_MONOTONIC) + config.fetch('request_interval').to_f
      end
    end

    def fetch(client, url)
      url = canonical_url(url)
      attempts = 0
      begin
        throttle
        LoggerManager.log_processed_file("HTTP GET #{url} thread=#{Thread.current.object_id}")
        page = client.get(url)
        canonical_url(page.uri.to_s)
        page
      rescue Mechanize::ResponseCodeError, Timeout::Error, SocketError, SystemCallError => e
        attempts += 1
        transient = !e.is_a?(Mechanize::ResponseCodeError) || [429, 500, 502, 503, 504].include?(e.response_code.to_i)
        raise unless transient && attempts <= config.fetch('retries')

        sleep(0.25 * (2**(attempts - 1)))
        retry
      end
    end

    def download_image(item, url, local_agent)
      image = fetch(local_agent, url)
      extensions = { 'image/png' => '.png', 'image/jpeg' => '.jpg', 'image/webp' => '.webp', 'image/gif' => '.gif' }
      extension = extensions[image.response['content-type'].to_s.split(';').first]
      raise 'Unsupported image content type' unless extension
      raise 'Image exceeds 10 MB' if image.body.bytesize > 10 * 1024 * 1024

      directory = File.join(@media_dir, ItemCollection.safe_name(item.category))
      FileUtils.mkdir_p(directory)
      path = File.join(directory, "#{ItemCollection.item_filename(item)}#{extension}")
      File.binwrite("#{path}.tmp", image.body)
      File.rename("#{path}.tmp", path)
      Pathname.new(path).relative_path_from(Pathname.new(@root)).to_s.tr('\\', '/')
    end
  end
end
