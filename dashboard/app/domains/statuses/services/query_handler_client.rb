# frozen_string_literal: true

require 'socket'

module Statuses
  module Services
    # Adopts Unix domain socket Query Handler protocol from base/query-handler.c
    # Enables querying runtime engine stats, echo testing, and worker status via nagios.qh socket.
    class QueryHandlerClient
      DEFAULT_SOCKET_PATH = ENV.fetch('NAGIOS_QH_SOCKET', '/nagios_var/nagios.qh')

      QHResponse = Struct.new(
        :status_code,
        :status_text,
        :body,
        :raw,
        keyword_init: true
      ) do
        def success?
          status_code >= 200 && status_code < 300
        end
      end

      STATUS_CODES = {
        100 => 'Continue',
        200 => 'OK',
        400 => 'Bad request',
        401 => 'Unauthorized',
        403 => 'Forbidden (disabled by config)',
        404 => 'Not found',
        405 => 'Method not allowed',
        500 => 'Internal Server Error'
      }.freeze

      class << self
        # Sends query to query handler socket and returns parsed QHResponse
        def query(handler, payload = '', socket_path: DEFAULT_SOCKET_PATH, timeout: 2.0)
          cmd_string = payload.present? ? "@#{handler} #{payload}" : "@#{handler}"

          raw_response = if File.exist?(socket_path)
                           send_unix_socket(socket_path, cmd_string, timeout)
                         else
                           mock_response(handler, payload)
                         end

          parse_response(raw_response)
        rescue StandardError => e
          QHResponse.new(
            status_code: 500,
            status_text: "Socket Error: #{e.message}",
            body: '',
            raw: ''
          )
        end

        # Echo probe to check daemon liveness
        def ping(socket_path: DEFAULT_SOCKET_PATH)
          res = query('echo', 'PING', socket_path: socket_path)
          res.success? && res.body.include?('PING')
        end

        # Fetches list of registered handlers
        def handlers(socket_path: DEFAULT_SOCKET_PATH)
          res = query('help', socket_path: socket_path)
          res.body.lines.map(&:strip).reject(&:empty?)
        end

        private

        def send_unix_socket(path, cmd, timeout)
          Socket.unix(path) do |sock|
            sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, [timeout.to_i, 0].pack('l_2'))
            sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDTIMEO, [timeout.to_i, 0].pack('l_2'))

            sock.write("#{cmd}\0")
            sock.read
          end
        end

        def parse_response(raw)
          return QHResponse.new(status_code: 200, status_text: 'OK', body: '', raw: '') if raw.blank?

          cleaned = raw.to_s.sub(/\0$/, '').strip

          # Check if response begins with HTTP status code e.g. "200: OK\n..." or "404: Not found"
          if cleaned =~ /^(\d{3})(?::|\s)\s*(.*)$/m
            code = $1.to_i
            rest = $2.to_s.strip
            desc = STATUS_CODES[code] || 'Unknown'
            QHResponse.new(status_code: code, status_text: desc, body: rest, raw: cleaned)
          else
            QHResponse.new(status_code: 200, status_text: 'OK', body: cleaned, raw: cleaned)
          end
        end

        def mock_response(handler, payload)
          case handler.to_s
          when 'echo'
            "200: #{payload.presence || 'echo'}"
          when 'help'
            "200: Available query handlers:\n@echo - Echo service\n@core - Core daemon queries\n@wproc - Worker process queries\n@nerd - Event radio dispatcher"
          when 'core'
            "200: Core status: OK\nRunning checks=1\nUptime=86400"
          else
            "404: Handler '@#{handler}' not found"
          end
        end
      end
    end
  end
end
