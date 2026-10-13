#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Pure-Ruby Nagios Plugin: check_tcp
# Standard Nagios Plugin API (0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN)
# ==============================================================================

require 'optparse'
require 'socket'
require 'timeout'

options = {
  host: '127.0.0.1',
  port: 80,
  warn: 1.0,
  crit: 3.0
}

OptionParser.new do |opts|
  opts.banner = 'Usage: check_tcp [options]'
  opts.on('-H', '--host HOST', 'Host address to check (default: 127.0.0.1)') { |v| options[:host] = v }
  opts.on('-p', '--port PORT', Integer, 'Port number to connect (default: 80)') { |v| options[:port] = v }
  opts.on('-w', '--warn SECONDS', Float, 'Warning response time (default: 1.0)') { |v| options[:warn] = v }
  opts.on('-c', '--crit SECONDS', Float, 'Critical response time (default: 3.0)') { |v| options[:crit] = v }
  opts.on('-h', '--help', 'Prints help') { puts opts; exit 3 }
end.parse!

begin
  t_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  Timeout.timeout(options[:crit]) do
    sock = Socket.tcp(options[:host], options[:port], connect_timeout: options[:crit])
    sock.close
  end

  t_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  duration = (t_end - t_start).round(4)
  perfdata = "time=#{duration}s;#{options[:warn]};#{options[:crit]};0;#{options[:crit]}"

  if duration >= options[:crit]
    puts "TCP CRITICAL - Response time #{duration}s exceeded critical threshold on #{options[:host]}:#{options[:port]} | #{perfdata}"
    exit 2
  elsif duration >= options[:warn]
    puts "TCP WARNING - Response time #{duration}s exceeded warning threshold on #{options[:host]}:#{options[:port]} | #{perfdata}"
    exit 1
  else
    puts "TCP OK - #{duration}s response time on #{options[:host]}:#{options[:port]} | #{perfdata}"
    exit 0
  end
rescue Timeout::Error
  puts "TCP CRITICAL - Connection to #{options[:host]}:#{options[:port]} timed out after #{options[:crit]}s | time=#{options[:crit]}s;#{options[:warn]};#{options[:crit]}"
  exit 2
rescue Errno::ECONNREFUSED
  puts "TCP CRITICAL - Connection refused by #{options[:host]}:#{options[:port]}"
  exit 2
rescue StandardError => e
  puts "TCP CRITICAL - Connection failed: #{e.message}"
  exit 2
end
