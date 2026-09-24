# frozen_string_literal: true

require 'bundler/setup'
require 'mongo'
Mongo::Logger.logger.level = Logger::ERROR
client = Mongo::Client.new(ENV.fetch('MONGODB_URI', 'mongodb://127.0.0.1:27017'),
                           database: 'admin', server_selection_timeout: 2)
begin
  client.database.command(shutdown: 1)
rescue Mongo::Error::SocketError
  # The server closes the connection while completing its normal shutdown.
ensure
  client.close
end
