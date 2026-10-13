#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Pure-Ruby Network Scanner & Device Discovery CLI
# ==============================================================================

require 'optparse'

# Boot Rails environment for domain services
require_relative '../config/environment'

options = {
  cidr: '127.0.0.1/32',
  community: 'public',
  timeout: 0.5,
  concurrency: 16
}

OptionParser.new do |opts|
  opts.banner = 'Usage: scan_network [options]'

  opts.on('-c', '--cidr CIDR', 'Network CIDR or IP (e.g. 192.168.1.0/24 or 127.0.0.1/32)') { |v| options[:cidr] = v }
  opts.on('-C', '--community COMMUNITY', 'SNMP community string (default: public)') { |v| options[:community] = v }
  opts.on('-t', '--timeout SECONDS', Float, 'Socket connection timeout (default: 0.5s)') { |v| options[:timeout] = v }
  opts.on('-w', '--workers COUNT', Integer, 'Concurrency thread pool size (default: 16)') { |v| options[:concurrency] = v }
  opts.on('-h', '--help', 'Display this help message and exit') do
    puts opts
    exit 0
  end
end.parse!

puts "\n" + ('=' * 80)
puts "  🌐 PURE-RUBY NETWORK SCANNER & DEVICE DISCOVERY"
puts "  Target Subnet : #{options[:cidr]}"
puts "  SNMP Comm     : #{options[:community]}"
puts "  Threads       : #{options[:concurrency]} workers"
puts ('=' * 80) + "\n"

puts "🔍 Scanning subnet #{options[:cidr]}..."
t_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

devices = Discovery::Services::NetworkScanner.scan_cidr(
  options[:cidr],
  community: options[:community],
  timeout: options[:timeout],
  concurrency: options[:concurrency]
)

t_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
duration = (t_end - t_start).round(2)

puts "✅ Scan completed in #{duration}s. Found #{devices.size} active device(s):\n\n"

if devices.empty?
  puts "  No devices responding on probed ports (80, 443, 22, 161, 8291, 53)."
else
  printf "%-17s %-22s %-16s %-18s %s\n", "IP ADDRESS", "HOSTNAME", "VENDOR", "TYPE", "OPEN PORTS"
  puts ('-' * 80)
  devices.each do |dev|
    printf "%-17s %-22s %-16s %-18s %s\n",
           dev.ip,
           dev.hostname.truncate(20),
           dev.vendor,
           dev.device_type,
           dev.open_ports.join(', ')
    if dev.snmp_descr.present?
      puts "    └─ SNMP: #{dev.snmp_descr.truncate(72)}"
    end
  end
end
puts "\n" + ('=' * 80) + "\n"
