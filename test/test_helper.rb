# frozen_string_literal: true

require 'minitest/autorun'
require 'minitest/mock'
require 'tmpdir'
require 'fileutils'
require 'base64'
require 'webrick'
require_relative '../libs/app_config_loader'
MyApplicationTokarchuk::AppConfigLoader.load_libs

class LabTest < Minitest::Test
  include MyApplicationTokarchuk

  def setup
    @temporary = Dir.mktmpdir('tokarchuk-test-')
    @config = AppConfigLoader.config
    @config['default']['root_dir'] = @temporary
    @config['logging']['level'] = 'DEBUG'
    LoggerManager.setup(@config['logging'], root: @temporary)
  end

  def teardown
    @server&.shutdown
    @server_thread&.join
    LoggerManager.close
    FileUtils.remove_entry(@temporary)
  end

  def product(name: 'Bulbasaur', price: 63, url: 'https://example.test/shop/bulbasaur')
    Item.new(name: name, price: price, source_url: url, category: 'Seed')
  end

  def start_fixture_server(broken: false)
    @active = @max_active = 0
    @server_mutex = Mutex.new
    @server = WEBrick::HTTPServer.new(Port: 0, BindAddress: '127.0.0.1', Logger: WEBrick::Log.new(File::NULL),
                                      AccessLog: [])
    @server.mount_proc('/') do |request, response|
      serve_fixture(request, response, broken)
    end
    @server_thread = Thread.new { @server.start }
    port = @server.listeners.first.addr[1]
    @config['web_scraping'].merge!('start_page' => "http://127.0.0.1:#{port}/shop/", 'threads' => 3,
                                   'max_products' => 6, 'max_pages' => 2, 'request_interval' => 0, 'retries' => 0)
  end

  def serve_fixture(request, response, broken)
    response['Content-Type'] = 'text/html; charset=utf-8'
    case request.path
    when '/robots.txt'
      response['Content-Type'] = 'text/plain'
      response.body = "User-agent: *\nDisallow: /blocked/\n"
    when '/shop/', '/shop/page/2/'
      indices = request.path == '/shop/' ? [1, 2, 3] : [3, 4, 5, 6]
      links = indices.map do |n|
        "<li class='product'><a class='woocommerce-LoopProduct-link' href='/product/#{n}'>P#{n}</a></li>"
      end
      response.body = "<ul class='products'>#{links.join}</ul>" \
                      "<a class='next page-numbers' href='/shop/page/2/'>next</a>"
    when %r{\A/product/\d+\z}
      n = request.path.split('/').last.to_i
      if broken && n == 2
        response.status = 404
      else
        response.body = delayed_product(n)
      end
    when '/image.png'
      response['Content-Type'] = 'image/png'
      png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII='
      response.body = Base64.decode64(png)
    else
      response.status = 404
    end
  end

  def delayed_product(number)
    @server_mutex.synchronize do
      @active += 1
      @max_active = [@max_active, @active].max
    end
    sleep 0.05
    product_html(number)
  ensure
    @server_mutex.synchronize { @active -= 1 }
  end

  def product_html(number)
    <<~HTML
      <html><body><h1 class="product_title">Pokemon #{number}</h1>
      <div class="summary"><p class="price"><span class="woocommerce-Price-amount">£#{number}.25</span></p></div>
      <div class="woocommerce-product-details__short-description">Опис Pokémon #{number}</div>
      <span class="posted_in"><a>Pokemon</a><a>Seed</a></span><span class="sku">#{number}</span>
      <div class="woocommerce-product-gallery__image"><a href="/image.png">image</a></div></body></html>
    HTML
  end
end
