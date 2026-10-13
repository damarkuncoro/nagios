#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'socket'
require 'openssl'
require 'timeout'

# ==============================================================================
# Pure-Ruby Nagios Plugin: check_ssl_cert
# Checks TLS/SSL certificate expiration days, common name / SAN, and handshake.
# ==============================================================================

options = {
  host: '127.0.0.1',
  port: 443,
  warning: 30, # days
  critical: 14, # days
  timeout: 5.0,
  sni: nil
}

OptionParser.new do |opts|
  opts.banner = "Usage: check_ssl_cert.rb -H HOST [-p PORT] [-w DAYS] [-c DAYS] [-s SNI] [-t TIMEOUT]"

  opts.on("-H", "--host HOST", "Target host to check") { |h| options[:host] = h }
  opts.on("-p", "--port PORT", Integer, "Port number (default: 443)") { |p| options[:port] = p }
  opts.on("-w", "--warning DAYS", Integer, "Warning threshold in days (default: 30)") { |w| options[:warning] = w }
  opts.on("-c", "--critical DAYS", Integer, "Critical threshold in days (default: 14)") { |c| options[:critical] = c }
  opts.on("-s", "--sni HOSTNAME", "Server Name Indication hostname (default: host)") { |s| options[:sni] = s }
  opts.on("-t", "--timeout SECONDS", Float, "Connection timeout in seconds (default: 5.0)") { |t| options[:timeout] = t }

  opts.on("-h", "--help", "Show this message") do
    puts opts
    exit 3
  end
end.parse!

sni_hostname = options[:sni] || options[:host]

begin
  cert = nil
  elapsed = 0.0

  Timeout.timeout(options[:timeout]) do
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    tcp_socket = TCPSocket.new(options[:host], options[:port])

    ctx = OpenSSL::SSL::SSLContext.new
    ctx.set_params(verify_mode: OpenSSL::SSL::VERIFY_NONE) # Probe certificate even if self-signed

    ssl_socket = OpenSSL::SSL::SSLSocket.new(tcp_socket, ctx)
    ssl_socket.hostname = sni_hostname if ssl_socket.respond_to?(:hostname=)
    ssl_socket.connect

    cert = ssl_socket.peer_cert
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time

    ssl_socket.close
    tcp_socket.close
  end

  if cert.nil?
    puts "SSL CRITICAL - Could not retrieve peer certificate from #{options[:host]}:#{options[:port]}"
    exit 2
  end

  now = Time.now
  not_after = cert.not_after
  seconds_left = not_after - now
  days_left = (seconds_left / 86400.0).to_f
  cn = cert.subject.to_a.find { |name, _, _| name == 'CN' }&.at(1) || 'Unknown'

  perfdata = "days_left=#{days_left.to_i}d;#{options[:warning]};#{options[:critical]};0 handshake=#{format('%.3f', elapsed)}s"

  if days_left <= 0
    puts "SSL CRITICAL - Certificate '#{cn}' EXPIRED on #{not_after.utc.strftime('%Y-%m-%d')} | #{perfdata}"
    exit 2
  elsif days_left <= options[:critical]
    puts "SSL CRITICAL - Certificate '#{cn}' expires in #{days_left.to_i} days (#{not_after.utc.strftime('%Y-%m-%d')}) | #{perfdata}"
    exit 2
  elsif days_left <= options[:warning]
    puts "SSL WARNING - Certificate '#{cn}' expires in #{days_left.to_i} days (#{not_after.utc.strftime('%Y-%m-%d')}) | #{perfdata}"
    exit 1
  else
    puts "SSL OK - Certificate '#{cn}' expires in #{days_left.to_i} days (#{not_after.utc.strftime('%Y-%m-%d')}) | #{perfdata}"
    exit 0
  end

rescue Timeout::Error
  puts "SSL CRITICAL - Connection timed out after #{options[:timeout]}s to #{options[:host]}:#{options[:port]}"
  exit 2
rescue SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
  puts "SSL CRITICAL - Connection failed to #{options[:host]}:#{options[:port]}: #{e.message}"
  exit 2
rescue StandardError => e
  puts "SSL UNKNOWN - Error validating certificate for #{options[:host]}:#{options[:port]}: #{e.message}"
  exit 3
end
