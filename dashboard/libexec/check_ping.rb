#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Pure-Ruby Nagios Plugin: check_ping
# Standard Nagios Plugin API (0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN)
# ==============================================================================

require 'optparse'
require 'socket'
require 'timeout'

options = {
  host: '127.0.0.1',
  warn_rta: 100.0,
  warn_pl: 20,
  crit_rta: 500.0,
  crit_pl: 60,
  packets: 2,
  timeout: 5,
  port: 80
}

OptionParser.new do |opts|
  opts.banner = 'Usage: check_ping -H <host> -w <wrta,wpl%> -c <crta,cpl%> [options]'

  opts.on('-H', '--host HOST', 'Host name or IP address to ping') { |v| options[:host] = v }
  opts.on('-w', '--warn THRESHOLD', 'Warning threshold <wrta,wpl%> (e.g. 100.0,20%)') do |v|
    rta, pl = v.split(',')
    options[:warn_rta] = rta.to_f if rta
    options[:warn_pl] = pl.to_i if pl
  end
  opts.on('-c', '--crit THRESHOLD', 'Critical threshold <crta,cpl%> (e.g. 500.0,60%)') do |v|
    rta, pl = v.split(',')
    options[:crit_rta] = rta.to_f if rta
    options[:crit_pl] = pl.to_i if pl
  end
  opts.on('-p', '--packets COUNT', Integer, 'Number of ICMP/probe packets to send (default: 2)') { |v| options[:packets] = v }
  opts.on('-t', '--timeout SECONDS', Integer, 'Connection timeout in seconds (default: 5)') { |v| options[:timeout] = v }
  opts.on('-P', '--port PORT', Integer, 'Fallback probe port when ping binary unavailable (default: 80)') { |v| options[:port] = v }
  opts.on('-h', '--help', 'Display this help and exit') do
    puts opts
    exit 3
  end
end.parse!

def ping_via_system(host, count, timeout)
  ping_bin = ['/bin/ping', '/usr/bin/ping', '/sbin/ping'].find { |p| File.executable?(p) }
  return nil unless ping_bin

  cmd = "#{ping_bin} -c #{count} -W #{timeout} #{host} 2>&1"
  out = `#{cmd}`
  return nil unless $CHILD_STATUS&.exitstatus || out.include?('packet')

  # Parse packet loss: e.g. "0% packet loss" or "0.0% packet loss"
  pl_match = out.match(/([0-9.]+)%\s*(?:packet\s*)?loss/i)
  packet_loss = pl_match ? pl_match[1].to_f.round : 100

  # Parse RTA: e.g. "round-trip min/avg/max/stddev = 0.045/0.051/0.060/0.005 ms"
  # or "rtt min/avg/max/mdev = 0.045/0.051/..."
  rta_match = out.match(%r{(?:round-trip|rtt)[^=]*=\s*[0-9.]+/([0-9.]+)/})
  rta = rta_match ? rta_match[1].to_f.round(2) : 0.0

  [packet_loss, rta]
rescue StandardError
  nil
end

def ping_via_pure_ruby(host, count, timeout, port)
  latencies = []
  lost = 0

  count.times do
    t_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    connected = false

    begin
      Timeout.timeout(timeout.to_f / count) do
        sock = Socket.tcp(host, port, connect_timeout: [1.0, timeout.to_f / count].min)
        sock.close
        connected = true
      end
    rescue Errno::ECONNREFUSED, Errno::ECONNRESET
      # Host reached and answered with TCP RST/Refused -> Host is alive!
      connected = true
    rescue Timeout::Error, Errno::EHOSTUNREACH, Errno::ENETUNREACH, SocketError
      lost += 1
    end

    t_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    latencies << ((t_end - t_start) * 1000.0) if connected
    sleep 0.05
  end

  packet_loss = ((lost.to_f / count) * 100.0).round
  rta = latencies.any? ? (latencies.sum / latencies.size).round(2) : 0.0

  [packet_loss, rta]
end

packet_loss, rta = ping_via_system(options[:host], options[:packets], options[:timeout])
packet_loss, rta = ping_via_pure_ruby(options[:host], options[:packets], options[:timeout], options[:port]) if packet_loss.nil?

perfdata = "rta=#{format('%.2f', rta)}ms;#{options[:warn_rta]};#{options[:crit_rta]};0; pl=#{packet_loss}%;#{options[:warn_pl]};#{options[:crit_pl]};0;100"

if packet_loss >= options[:crit_pl] || (rta > 0 && rta >= options[:crit_rta])
  puts "PING CRITICAL - Packet loss = #{packet_loss}%, RTA = #{format('%.2f', rta)} ms | #{perfdata}"
  exit 2
elsif packet_loss >= options[:warn_pl] || (rta > 0 && rta >= options[:warn_rta])
  puts "PING WARNING - Packet loss = #{packet_loss}%, RTA = #{format('%.2f', rta)} ms | #{perfdata}"
  exit 1
else
  puts "PING OK - Packet loss = #{packet_loss}%, RTA = #{format('%.2f', rta)} ms | #{perfdata}"
  exit 0
end
