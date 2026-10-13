#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'
require 'resolv'
require 'timeout'

# ==============================================================================
# Pure-Ruby Nagios Plugin: check_dns
# Measures DNS hostname resolution latency and validates record answers.
# ==============================================================================

options = {
  host: nil,
  server: nil,
  warning: 500.0, # ms
  critical: 1500.0, # ms
  timeout: 5.0
}

OptionParser.new do |opts|
  opts.banner = "Usage: check_dns.rb -H HOSTNAME [-s NAMESERVER] [-w WARN_MS] [-c CRIT_MS] [-t TIMEOUT]"

  opts.on("-H", "--host HOSTNAME", "DNS hostname to resolve") { |h| options[:host] = h }
  opts.on("-s", "--server SERVER", "Nameserver IP to query (default: system resolver)") { |s| options[:server] = s }
  opts.on("-w", "--warning MS", Float, "Warning threshold latency in ms (default: 500)") { |w| options[:warning] = w }
  opts.on("-c", "--critical MS", Float, "Critical threshold latency in ms (default: 1500)") { |c| options[:critical] = c }
  opts.on("-t", "--timeout SECONDS", Float, "Timeout in seconds (default: 5.0)") { |t| options[:timeout] = t }

  opts.on("-h", "--help", "Show this message") do
    puts opts
    exit 3
  end
end.parse!

if options[:host].nil? || options[:host].to_s.strip.empty?
  puts "DNS UNKNOWN - No hostname specified (-H HOSTNAME required)"
  exit 3
end

begin
  resolver_config = options[:server] ? { nameserver: [options[:server]] } : nil
  resolver = resolver_config ? Resolv::DNS.new(resolver_config) : Resolv::DNS.new
  resolver.timeouts = options[:timeout]

  addresses = []
  latency_ms = 0.0

  Timeout.timeout(options[:timeout]) do
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    addresses = resolver.getresources(options[:host], Resolv::DNS::Resource::IN::A).map { |r| r.address.to_s }
    if addresses.empty?
      # Try AAAA if no A records found
      addresses = resolver.getresources(options[:host], Resolv::DNS::Resource::IN::AAAA).map { |r| r.address.to_s }
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time
    latency_ms = (elapsed * 1000.0).round(2)
  end

  if addresses.empty?
    puts "DNS CRITICAL - No records found for #{options[:host]}"
    exit 2
  end

  perfdata = "rta=#{latency_ms}ms;#{options[:warning]};#{options[:critical]};0"
  addr_str = addresses.take(3).join(', ')

  if latency_ms >= options[:critical]
    puts "DNS CRITICAL - #{options[:host]} resolved to #{addr_str} in #{latency_ms}ms | #{perfdata}"
    exit 2
  elsif latency_ms >= options[:warning]
    puts "DNS WARNING - #{options[:host]} resolved to #{addr_str} in #{latency_ms}ms | #{perfdata}"
    exit 1
  else
    puts "DNS OK - #{options[:host]} resolved to #{addr_str} in #{latency_ms}ms | #{perfdata}"
    exit 0
  end

rescue Resolv::ResolvError => e
  puts "DNS CRITICAL - Resolution failed for #{options[:host]}: #{e.message}"
  exit 2
rescue Timeout::Error
  puts "DNS CRITICAL - Timeout after #{options[:timeout]}s resolving #{options[:host]}"
  exit 2
rescue StandardError => e
  puts "DNS UNKNOWN - Error resolving #{options[:host]}: #{e.message}"
  exit 3
end
