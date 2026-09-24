# frozen_string_literal: true

require_relative '../lib/main'
require 'socket'
require 'timeout'
require 'rbconfig'
require 'fileutils'

module MyApplicationTokarchuk
  class DesktopLauncher
    ROOT = File.expand_path('..', __dir__)
    REDIS = 'tmp/tools/redis/Redis-7.4.9-Windows-x64-msys2/redis-server.exe'

    def run(arguments)
      return CLI.run(arguments) if arguments.intersect?(%w[--help -h --show-config])

      Dir.chdir(ROOT) do
        FileUtils.mkdir_p('tmp')
        File.open('tmp/desktop.lock', 'w') do |lock|
          raise 'Another catalog run is active. Wait for it to finish.' unless lock.flock(File::LOCK_EX | File::LOCK_NB)

          execute(arguments)
        end
      end
    rescue StandardError => e
      warn "Launch failed: #{e.message}"
      1
    end

    private

    def execute(arguments)
      check_setup
      start_redis
      start_worker
      puts 'Collecting catalog -> SQLite + MongoDB -> ZIP -> email...'
      CLI.run(arguments + %w[--mongodb --send-archive], after_run: method(:wait_for_delivery))
    ensure
      stop_child(@worker_pid)
      stop_child(@redis_pid)
      ENV['REDIS_URL'] = @previous_redis_url if @redis_environment_changed
    end

    def check_setup
      AppConfigLoader.load_libs
      raise 'Run scripts/run.ps1 install to prepare portable Redis.' unless File.file?(REDIS)

      required = %w[SMTP_HOST SMTP_FROM SMTP_USER SMTP_PASSWORD ARCHIVE_EMAIL]
      return if required.all? { |name| !ENV[name].to_s.empty? }

      raise 'Email is not configured. Run setup_smtp.cmd first.'
    end

    def start_redis
      reservation = TCPServer.new('127.0.0.1', 0)
      port = reservation.addr[1]
      reservation.close
      File.write('tmp/desktop-redis.conf',
                 "bind 127.0.0.1\nport #{port}\nprotected-mode yes\nsave \"\"\nappendonly no\n")
      @previous_redis_url = ENV.fetch('REDIS_URL', nil)
      @redis_environment_changed = true
      ENV['REDIS_URL'] = "redis://127.0.0.1:#{port}/0"
      @redis_pid = spawn_logged(REDIS, 'tmp/desktop-redis.conf', log: 'tmp/desktop-redis.log')
      wait_for_redis(port)
    end

    def wait_for_redis(port)
      Timeout.timeout(15) do
        loop do
          socket = TCPSocket.new('127.0.0.1', port)
          socket.write("PING\r\n")
          return if socket.gets == "+PONG\r\n"
        rescue SystemCallError
          sleep 0.2
        ensure
          socket&.close
        end
      end
    end

    def start_worker
      @worker_pid = spawn_logged(RbConfig.ruby, Gem.bin_path('sidekiq', 'sidekiq'),
                                 '-r', './config/sidekiq_boot.rb', '-q', 'archives', '-c', '2',
                                 log: 'tmp/desktop-worker.log')
    end

    def spawn_logged(*command, log:)
      options = { out: log, err: %i[child out], chdir: ROOT }
      options[:new_pgroup] = true if Gem.win_platform?
      Process.spawn(*command, **options)
    end

    def wait_for_delivery(engine)
      receipt = "#{engine.archive_path}.sent.json"
      puts 'Waiting for SMTP confirmation...'
      Timeout.timeout(120) do
        until File.file?(receipt)
          if Process.waitpid(@worker_pid, Process::WNOHANG)
            @worker_pid = nil
            raise 'Email worker stopped. See tmp/desktop-worker.log.'
          end
          sleep 0.5
        end
      end
      puts "SMTP accepted the archive for #{ENV.fetch('ARCHIVE_EMAIL')}."
    rescue Timeout::Error
      raise 'Email delivery not confirmed. See tmp/desktop-worker.log; the ZIP remains in output/archives.'
    end

    def stop_child(pid)
      return unless pid

      Process.kill('KILL', pid)
      Process.wait(pid)
    rescue Errno::ESRCH, Errno::ECHILD
      nil
    end
  end
end

if $PROGRAM_NAME == __FILE__
  $stdout.sync = true
  exit MyApplicationTokarchuk::DesktopLauncher.new.run(ARGV)
end
