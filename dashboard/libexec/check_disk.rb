#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Pure-Ruby Nagios Plugin: check_disk
# Standard Nagios Plugin API (0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN)
# ==============================================================================

require 'optparse'

options = {
  path: '/',
  warn_pct: 80,
  crit_pct: 90
}

OptionParser.new do |opts|
  opts.banner = 'Usage: check_disk [options]'
  opts.on('-p', '--path PATH', 'Path to check (default: /)') { |v| options[:path] = v }
  opts.on('-w', '--warn PERCENT', Integer, 'Warning used threshold percent (default: 80)') { |v| options[:warn_pct] = v }
  opts.on('-c', '--crit PERCENT', Integer, 'Critical used threshold percent (default: 90)') { |v| options[:crit_pct] = v }
  opts.on('-h', '--help', 'Prints help') { puts opts; exit 3 }
end.parse!

begin
  df_output = `df -k #{options[:path]} 2>/dev/null`
  lines = df_output.strip.split("\n")
  if lines.size < 2
    puts "DISK UNKNOWN - Could not retrieve disk metrics for #{options[:path]}"
    exit 3
  end

  # Filesystem 1K-blocks Used Available Use% Mounted on
  parts = lines[1].split(/\s+/)
  total_kb = parts[1].to_f
  used_kb = parts[2].to_f
  avail_kb = parts[3].to_f
  used_pct = parts[4].to_s.sub('%', '').to_i

  total_gb = (total_kb / 1024 / 1024).round(1)
  used_gb = (used_kb / 1024 / 1024).round(1)
  avail_gb = (avail_kb / 1024 / 1024).round(1)

  perfdata = "used=#{used_gb}GB;#{total_gb * options[:warn_pct] / 100};#{total_gb * options[:crit_pct] / 100};0;#{total_gb} free=#{avail_gb}GB"

  if used_pct >= options[:crit_pct]
    puts "DISK CRITICAL - #{used_pct}% used (#{used_gb}GB / #{total_gb}GB) on #{options[:path]} | #{perfdata}"
    exit 2
  elsif used_pct >= options[:warn_pct]
    puts "DISK WARNING - #{used_pct}% used (#{used_gb}GB / #{total_gb}GB) on #{options[:path]} | #{perfdata}"
    exit 1
  else
    puts "DISK OK - #{avail_gb}GB free (#{used_pct}% used) on #{options[:path]} | #{perfdata}"
    exit 0
  end
rescue StandardError => e
  puts "DISK UNKNOWN - Execution failed: #{e.message}"
  exit 3
end
