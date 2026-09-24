# frozen_string_literal: true

require 'net/smtp'
require 'socket'

begin
  smtp = Net::SMTP.new(ENV.fetch('SMTP_HOST'), Integer(ENV.fetch('SMTP_PORT', '587')))
  smtp.open_timeout = 10
  smtp.read_timeout = 20
  smtp.enable_starttls
  smtp.start(Socket.gethostname, ENV.fetch('SMTP_USER'), ENV.fetch('SMTP_PASSWORD'), :plain) do
    puts 'SMTP authentication successful. No email was sent.'
  end
rescue StandardError => e
  warn "SMTP authentication failed (#{e.class}). Check the app password, account policy and network."
  exit 1
end
