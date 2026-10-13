#!/usr/bin/env ruby
# frozen_string_literal: true

require 'optparse'

# ==============================================================================
# Pure-Ruby Nagios Plugin: check_process
# Monitors running system process instances by command name.
# ==============================================================================

options = {
  command: nil,
  warning: '1:50',
  critical: '1:100'
}

OptionParser.new do |opts|
  opts.banner = "Usage: check_process.rb -C COMMAND [-w MIN:MAX] [-c MIN:MAX]"

  opts.on("-C", "--command COMMAND", "Process command name to match (case-insensitive substring)") do |c|
    options[:command] = c
  end

  opts.on("-w", "--warning RANGE", "Warning threshold range [MIN:MAX] (default: 1:50)") do |w|
    options[:warning] = w
  end

  opts.on("-c", "--critical RANGE", "Critical threshold range [MIN:MAX] (default: 1:100)") do |c|
    options[:critical] = c
  end

  opts.on("-h", "--help", "Show this message") do
    puts opts
    exit 3
  end
end.parse!

if options[:command].nil? || options[:command].to_s.strip.empty?
  puts "PROCS UNKNOWN - No command name specified (-C COMMAND required)"
  exit 3
end

def parse_range(range_str)
  parts = range_str.to_s.split(':')
  if parts.size == 2
    min = parts[0].empty? ? 0 : parts[0].to_i
    max = parts[1].empty? ? Float::INFINITY : parts[1].to_i
    [min, max]
  else
    val = range_str.to_i
    [0, val]
  end
end

w_min, w_max = parse_range(options[:warning])
c_min, c_max = parse_range(options[:critical])

# Enumerate processes using ps
ps_output = `ps -eo comm 2>/dev/null`
pattern = Regexp.new(Regexp.escape(options[:command]), Regexp::IGNORECASE)

matching_count = ps_output.lines.count do |line|
  cmd = line.strip
  cmd =~ pattern
end

perfdata = "procs=#{matching_count};#{options[:warning]};#{options[:critical]};0"

if matching_count < c_min || matching_count > c_max
  puts "PROCS CRITICAL - #{matching_count} processes matching '#{options[:command]}' | #{perfdata}"
  exit 2
elsif matching_count < w_min || matching_count > w_max
  puts "PROCS WARNING - #{matching_count} processes matching '#{options[:command]}' | #{perfdata}"
  exit 1
else
  puts "PROCS OK - #{matching_count} processes matching '#{options[:command]}' | #{perfdata}"
  exit 0
end
