# frozen_string_literal: true

require_relative '../libs/app_config_loader'
MyApplicationTokarchuk::AppConfigLoader.load_libs
configuration = MyApplicationTokarchuk::AppConfigLoader.config
MyApplicationTokarchuk::LoggerManager.setup(configuration['logging'], root: configuration['default']['root_dir'])
MyApplicationTokarchuk::ArchiveSender.configure_background(configuration)
