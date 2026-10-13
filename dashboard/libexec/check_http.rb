#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Pure-Ruby Nagios Plugin: check_http
# Standard Nagios Plugin API (0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN)
# ==============================================================================

require 'optparse'
require 'net/http'
require 'uri'

options = {
  url: 'http://127.0.0.1:3000/healthz',
  warn: 2.0,
  crit: 5.0,
  expected_status: 200
}

OptionParser.new do |opts|
  opts.banner = 'Usage: check_http [options]'
  opts.on('-u', '--url URL', 'URL to check (default: http://127.0.0.1:3000/healthz)') { |v| options[:url] = v }
  opts.on('-w', '--warn SECONDS', Float, 'Warning threshold in seconds (default: 2.0)') { |v| options[:warn] = v }
  opts.on('-c', '--crit SECONDS', Float, 'Critical threshold in seconds (default: 5.0)') { |v| options[:crit] = v }
  opts.on('-s', '--status CODE', Integer, 'Expected HTTP status code (default: 200)') { |v| options[:expected_status] = v }
  opts.on('-h', '--help', 'Prints help') { puts opts; exit 3 }
end.parse!

begin
  uri = URI.parse(options[:url])
  t_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = (uri.scheme == 'https')
  http.open_timeout = options[:crit]
  http.read_timeout = options[:crit]

  path = uri.request_uri.to_s.empty? ? '/' : uri.request_uri
  request = Net::HTTP::Get.new(path)
  response = http.request(request)

  t_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  duration = (t_end - t_start).round(3)
  perfdata = "time=#{duration}s;#{options[:warn]};#{options[:crit]};0;10"

  status_code = response.code.to_i

  if status_code != options[:expected_status]
    puts "HTTP CRITICAL - Unexpected status #{status_code} (expected #{options[:expected_status]}) | #{perfdata}"
    exit 2
  elsif duration >= options[:crit]
    puts "HTTP CRITICAL - Latency #{duration}s exceeded critical threshold #{options[:crit]}s | #{perfdata}"
    exit 2
  elsif duration >= options[:warn]
    puts "HTTP WARNING - Latency #{duration}s exceeded warning threshold #{options[:warn]}s | #{perfdata}"
    exit 1
  else
    puts "HTTP OK - HTTP/#{response.http_version} #{status_code} #{response.message} (#{duration}s) | #{perfdata}"
    exit 0
  end
rescue Timeout::Error
  puts "HTTP CRITICAL - Connection timed out after #{options[:crit]}s | time=#{options[:crit]}s;#{options[:warn]};#{options[:crit]}"
  exit 2
rescue StandardError => e
  puts "HTTP CRITICAL - Connection failed: #{e.message} | time=0s;#{options[:warn]};#{options[:crit]}"
  exit 2
end
