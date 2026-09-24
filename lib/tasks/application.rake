# frozen_string_literal: true

desc 'Run the catalog scraper (optional ARGS="--limit 5")'
task :run do
  require 'shellwords'
  ruby File.expand_path('../../main.rb', __dir__), *Shellwords.split(ENV.fetch('ARGS', ''))
end

desc 'Check Ruby style with RuboCop'
task :lint do
  sh 'bundle exec rubocop'
end

desc 'Show available execution switches'
task :config do
  require_relative '../../libs/app_config_loader'
  MyApplicationTokarchuk::AppConfigLoader.load_libs
  puts MyApplicationTokarchuk::Configurator.available_methods
end
