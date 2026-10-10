# frozen_string_literal: true

require 'socket'
require 'timeout'

module Statuses
  module Services
    # Adopts TCP connection testing and network helpers from base/netutils.c
    # Implements my_tcp_connect socket probe with timeout and DNS resolution.
    class NetUtils
      ProbeResult = Struct.new(
        :success,
        :host,
        :port,
        :latency_ms,
        :error,
        keyword_init: true
      ) do
        def success?
          success == true
        end
      end

      class << self
        # Probes TCP port connection with timeout (base/netutils.c my_tcp_connect)
        def tcp_connect(host, port, timeout: 2.0)
          t_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          success = false
          err_msg = nil

          begin
            Timeout.timeout(timeout) do
              sock = TCPSocket.new(host, port)
              sock.close
              success = true
            end
          rescue StandardError => e
            success = false
            err_msg = e.message
          end

          t_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          latency = ((t_end - t_start) * 1000.0).round(2)

          ProbeResult.new(
            success: success,
            host: host,
            port: port.to_i,
            latency_ms: latency,
            error: err_msg
          )
        end

        # Resolves hostname to IP address
        def resolve_address(host)
          return host if host =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/

          Addrinfo.getaddrinfo(host, nil, :INET).first&.ip_address
        rescue StandardError
          nil
        end

        # Checks whether port number is valid
        def valid_port?(port)
          p = port.to_i
          p.positive? && p <= 65535
        end
      end
    end
  end
end
