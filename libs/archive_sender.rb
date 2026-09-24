# frozen_string_literal: true

require 'sidekiq'
require 'pony'
require_relative 'app_config_loader'
require_relative 'logger_manager'

module MyApplicationTokarchuk
  class ArchiveSender
    include Sidekiq::Job

    sidekiq_options queue: 'archives', retry: 3

    def self.configure_background(config)
      redis = { url: config.fetch('background').fetch('redis_url') }
      Sidekiq.configure_client { |client| client.redis = redis }
      Sidekiq.configure_server { |server| server.redis = redis }
    end

    def perform(relative_archive, recipient)
      config = AppConfigLoader.config
      root = config.fetch('default').fetch('root_dir')
      archive_dir = File.expand_path(config.fetch('archive').fetch('directory'), root)
      archive = File.realpath(File.expand_path(relative_archive, root))
      unless archive.start_with?("#{File.realpath(archive_dir)}/") && File.extname(archive) == '.zip'
        raise ArgumentError, 'Only a generated archive can be sent'
      end

      settings = config.fetch('mail')
      if recipient.to_s.empty? || settings['from'].to_s.empty?
        raise ArgumentError,
              'Recipient and SMTP_FROM are required'
      end

      Pony.mail(to: recipient, from: settings.fetch('from'), subject: settings.fetch('subject'),
                charset: 'UTF-8',
                body: 'Результати збору каталогу додано до листа у ZIP-архіві.', via: :smtp,
                via_options: smtp_options(settings), attachments: { File.basename(archive) => File.binread(archive) })
      LoggerManager.log_processed_file("Archive delivered: #{File.basename(archive)}")
      File.write("#{archive}.sent.json", JSON.generate(recipient: recipient, sent_at: Time.now.utc.iso8601, jid: jid))
    rescue StandardError => e
      LoggerManager.log_error("ArchiveSender failed: #{e.class}")
      raise
    end

    private

    def smtp_options(settings)
      options = { address: settings.fetch('smtp_host'), port: Integer(settings.fetch('smtp_port')),
                  enable_starttls_auto: settings.fetch('smtp_starttls'), open_timeout: 10, read_timeout: 30 }
      unless settings['smtp_user'].to_s.empty?
        options.merge!(user_name: settings['smtp_user'], password: settings.fetch('smtp_password'),
                       authentication: settings.fetch('smtp_authentication').to_sym)
      end
      options
    end
  end
end
