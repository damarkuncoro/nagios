#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'

# ==============================================================================
# Pure-Ruby Nagios Plugin: check_load
# Measures 1, 5, and 15-minute system load averages.
# Supported on Linux (/proc/loadavg) and Unix/macOS (uptime fallback).
# ==============================================================================

options = {
  warning: [5.0, 4.0, 3.0],
  critical: [10.0, 8.0, 6.0]
}

OptionParser.new do |opts|
  opts.banner = "Usage: check_load.rb -w WLOAD1,WLOAD5,WLOAD15 -c CLOAD1,CLOAD5,CLOAD15"

  opts.on("-w", "--warning W1,W5,W15", "Warning threshold for 1m, 5m, 15m load (e.g., 5.0,4.0,3.0)") do |w|
    vals = w.to_s.split(',').map { |v| Float(v.strip) rescue nil }.compact
    options[:warning] = vals if vals.size == 3
  end

  opts.on("-c", "--critical C1,C5,C15", "Critical threshold for 1m, 5m, 15m load (e.g., 10.0,8.0,6.0)") do |c|
    vals = c.to_s.split(',').map { |v| Float(v.strip) rescue nil }.compact
    options[:critical] = vals if vals.size == 3
  end

  opts.on("-h", "--help", "Show this message") do
    puts opts
    exit 3
  end
end.parse!

def read_load_averages
  if File.exist?('/proc/loadavg')
    parts = File.read('/proc/loadavg').split
    [parts[0].to_f, parts[1].to_f, parts[2].to_f]
  else
    # Fallback to uptime command
    uptime_output = `uptime 2>/dev/null`
    if uptime_output =~ /load averages?:\s*([0-9.]+)[,\s]+([0-9.]+)[,\s]+([0-9.]+)/i
      [$1.to_f, $2.to_f, $3.to_f]
    else
      [0.0, 0.0, 0.0]
    end
  end
rescue StandardError
  nil
end

loads = read_load_averages
if loads.nil?
  puts "LOAD UNKNOWN - Unable to read system load average"
  exit 3
end

l1, l5, l15 = loads
w1, w5, w15 = options[:warning]
c1, c5, c15 = options[:critical]

perfdata = "load1=#{format('%.2f', l1)};#{w1};#{c1};0 load5=#{format('%.2f', l5)};#{w5};#{c5};0 load15=#{format('%.2f', l15)};#{w15};#{c15};0"

if l1 >= c1 || l5 >= c5 || l15 >= c15
  puts "LOAD CRITICAL - load average: #{format('%.2f', l1)}, #{format('%.2f', l5)}, #{format('%.2f', l15)} | #{perfdata}"
  exit 2
elsif l1 >= w1 || l5 >= w5 || l15 >= w15
  puts "LOAD WARNING - load average: #{format('%.2f', l1)}, #{format('%.2f', l5)}, #{format('%.2f', l15)} | #{perfdata}"
  exit 1
else
  puts "LOAD OK - load average: #{format('%.2f', l1)}, #{format('%.2f', l5)}, #{format('%.2f', l15)} | #{perfdata}"
  exit 0
end
