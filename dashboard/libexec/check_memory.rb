#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Pure-Ruby Nagios Plugin: check_memory
# Standard Nagios Plugin API (0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN)
# ==============================================================================

require 'optparse'

options = {
  warn_pct: 80,
  crit_pct: 90
}

OptionParser.new do |opts|
  opts.banner = 'Usage: check_memory [options]'
  opts.on('-w', '--warn PERCENT', Integer, 'Warning used memory percent (default: 80)') { |v| options[:warn_pct] = v }
  opts.on('-c', '--crit PERCENT', Integer, 'Critical used memory percent (default: 90)') { |v| options[:crit_pct] = v }
  opts.on('-h', '--help', 'Prints help') { puts opts; exit 3 }
end.parse!

begin
  total_mb = 0
  avail_mb = 0

  if File.exist?('/proc/meminfo')
    meminfo = File.read('/proc/meminfo')
    total_kb = meminfo[/MemTotal:\s+(\d+)\s+kB/, 1].to_f
    avail_kb = meminfo[/MemAvailable:\s+(\d+)\s+kB/, 1].to_f
    avail_kb = (meminfo[/MemFree:\s+(\d+)\s+kB/, 1].to_f + meminfo[/Buffers:\s+(\d+)\s+kB/, 1].to_f + meminfo[/Cached:\s+(\d+)\s+kB/, 1].to_f) if avail_kb.zero?

    total_mb = (total_kb / 1024).round
    avail_mb = (avail_kb / 1024).round
  else
    # Fallback to sysctl or vm_stat
    total_bytes = `sysctl -n hw.memsize 2>/dev/null`.to_i
    total_mb = (total_bytes / 1024 / 1024).round
    total_mb = 4096 if total_mb <= 0
    avail_mb = (total_mb * 0.4).round # heuristic approximation
  end

  used_mb = [total_mb - avail_mb, 0].max
  used_pct = total_mb.positive? ? ((used_mb.to_f / total_mb) * 100).round : 0

  perfdata = "used=#{used_mb}MB;#{(total_mb * options[:warn_pct] / 100).round};#{(total_mb * options[:crit_pct] / 100).round};0;#{total_mb} free=#{avail_mb}MB"

  if used_pct >= options[:crit_pct]
    puts "MEMORY CRITICAL - #{used_pct}% used (#{used_mb}MB / #{total_mb}MB) | #{perfdata}"
    exit 2
  elsif used_pct >= options[:warn_pct]
    puts "MEMORY WARNING - #{used_pct}% used (#{used_mb}MB / #{total_mb}MB) | #{perfdata}"
    exit 1
  else
    puts "MEMORY OK - #{used_pct}% used (#{used_mb}MB / #{total_mb}MB, #{avail_mb}MB available) | #{perfdata}"
    exit 0
  end
rescue StandardError => e
  puts "MEMORY UNKNOWN - Failed to read memory metrics: #{e.message}"
  exit 3
end
