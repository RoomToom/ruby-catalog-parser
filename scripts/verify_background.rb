# frozen_string_literal: true

# Local-only integration check: a real Sidekiq process sends to an SMTP capture
# server on 127.0.0.1. No external recipient or SMTP service is contacted.
require 'bundler/setup'
require 'socket'
require 'timeout'
require 'rbconfig'
require 'mail'
require_relative '../libs/app_config_loader'
MyApplicationTokarchuk::AppConfigLoader.load_libs

module MyApplicationTokarchuk
  class BackgroundVerification
    def run
      root = AppConfigLoader::ROOT
      redis_url = ENV.fetch('TEST_REDIS_URL')
      uri = URI.parse(redis_url)
      raise 'Use a dedicated local Redis instance' unless %w[127.0.0.1 localhost].include?(uri.host)

      archive = Dir.glob(File.join(root, 'output/archives/*.zip')).max
      raise 'Run the application to create an archive first' unless archive

      FileUtils.mkdir_p(File.join(root, 'tmp'))
      server = TCPServer.new('127.0.0.1', 0)
      capture = Thread.new { receive_message(server) }
      worker = start_worker(smtp_environment(server, redis_url), root)
      config = AppConfigLoader.config
      config['background']['redis_url'] = redis_url
      ArchiveSender.configure_background(config)
      relative = Pathname.new(archive).relative_path_from(Pathname.new(root)).to_s.tr('\\', '/')
      jid = ArchiveSender.perform_async(relative, 'student@example.test')
      raw = Timeout.timeout(30) { capture.value }
      verify_message(raw, archive)
      File.write(File.join(root, 'tmp/background-test.eml'), raw)
      puts "PASS: Redis -> Sidekiq worker PID #{worker} -> Pony -> local SMTP; job #{jid}"
    ensure
      server&.close
      capture&.kill if capture&.alive?
      if worker
        Process.kill('KILL', worker)
        Process.wait(worker)
      end
    end

    private

    def smtp_environment(server, redis_url)
      { 'REDIS_URL' => redis_url, 'SMTP_HOST' => '127.0.0.1',
        'SMTP_PORT' => server.addr[1].to_s, 'SMTP_FROM' => 'lab@example.test',
        'SMTP_USER' => '', 'SMTP_PASSWORD' => '', 'SMTP_STARTTLS' => 'false' }
    end

    def start_worker(environment, root)
      executable = Gem.bin_path('sidekiq', 'sidekiq')
      log = File.join(root, 'tmp/sidekiq-verification.log')
      Process.spawn(environment, RbConfig.ruby, executable, '-r', File.join(root, 'config/sidekiq_boot.rb'),
                    '-q', 'archives', '-c', '2', out: log, err: log, chdir: root)
    end

    def receive_message(server)
      socket = server.accept
      socket.write("220 localhost test SMTP\r\n")
      content = +''
      while (line = socket.gets)
        case line
        when /\ADATA/i
          socket.write("354 End with a dot\r\n")
          while (data = socket.gets) && data != ".\r\n"
            content << data.sub(/\A\.\./, '.')
          end
          socket.write("250 Captured locally\r\n")
        when /\AQUIT/i
          socket.write("221 Bye\r\n")
          break
        else
          socket.write("250 OK\r\n")
        end
      end
      content
    ensure
      socket&.close
    end

    def verify_message(raw, archive)
      message = Mail.read_from_string(raw)
      raise 'Wrong local test recipient' unless message.to == ['student@example.test']
      raise 'Missing ZIP attachment' unless message.attachments.size == 1
      raise 'ZIP attachment bytes differ' unless message.attachments.first.decoded == File.binread(archive)
    end
  end
end

MyApplicationTokarchuk::BackgroundVerification.new.run
