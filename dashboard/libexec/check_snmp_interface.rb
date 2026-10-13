#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Pure-Ruby Nagios Plugin: check_snmp_interface
# Standard Nagios Plugin API (0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN)
# Monitors Switch/Router interface link operational status and traffic counters.
# ==============================================================================

require 'optparse'
require 'socket'
require 'openssl'
require 'timeout'

options = {
  host: '127.0.0.1',
  port: 161,
  community: 'public',
  interface: '1',
  timeout: 4
}

OptionParser.new do |opts|
  opts.banner = 'Usage: check_snmp_interface -H <host> -i <index_or_name> [options]'

  opts.on('-H', '--host HOST', 'Target router/switch IP address') { |v| options[:host] = v }
  opts.on('-p', '--port PORT', Integer, 'SNMP UDP port (default: 161)') { |v| options[:port] = v }
  opts.on('-C', '--community COMMUNITY', 'SNMP community string (default: public)') { |v| options[:community] = v }
  opts.on('-i', '--interface INDEX', 'Interface index number (e.g. 1, 2, 3...)') { |v| options[:interface] = v }
  opts.on('-t', '--timeout SECONDS', Integer, 'Timeout in seconds (default: 4)') { |v| options[:timeout] = v }
  opts.on('-h', '--help', 'Display this help message and exit') do
    puts opts
    exit 3
  end
end.parse!

def query_oid(host, port, community, oid, timeout)
  sock = UDPSocket.new
  sock.connect(host, port)

  varbind = OpenSSL::ASN1::Sequence.new([
    OpenSSL::ASN1::ObjectId.new(oid.sub(/^\./, '')),
    OpenSSL::ASN1::Null.new(nil)
  ])
  pdu = OpenSSL::ASN1::ASN1Data.new([
    OpenSSL::ASN1::Integer.new(rand(1000..99_999)),
    OpenSSL::ASN1::Integer.new(0),
    OpenSSL::ASN1::Integer.new(0),
    OpenSSL::ASN1::Sequence.new([varbind])
  ], 0, :CONTEXT_SPECIFIC)

  msg = OpenSSL::ASN1::Sequence.new([
    OpenSSL::ASN1::Integer.new(1), # SNMPv2c
    OpenSSL::ASN1::OctetString.new(community),
    pdu
  ])

  sock.send(msg.to_der, 0)
  ready = IO.select([sock], nil, nil, timeout)
  unless ready
    sock.close
    return [:error, "Timeout after #{timeout}s"]
  end

  data, _ = sock.recvfrom(4096)
  sock.close
  decoded = OpenSSL::ASN1.decode(data)
  vb = decoded.value[2].value[3].value.first
  val_node = vb.value[1]
  val = val_node.is_a?(OpenSSL::BN) ? val_node.to_i : val_node.value
  [:ok, val]
rescue StandardError => e
  sock&.close rescue nil
  [:error, e.message]
end

idx = options[:interface].to_i
idx = 1 if idx <= 0

# Query ifDescr, ifOperStatus, ifInOctets, ifOutOctets
st_descr, descr = query_oid(options[:host], options[:port], options[:community], "1.3.6.1.2.1.2.2.1.2.#{idx}", options[:timeout])
if st_descr == :error
  puts "INTERFACE CRITICAL - Failed to query interface ##{idx} on #{options[:host]}: #{descr}"
  exit 2
end

_st_oper, oper_status = query_oid(options[:host], options[:port], options[:community], "1.3.6.1.2.1.2.2.1.8.#{idx}", options[:timeout])
_st_in, in_octets = query_oid(options[:host], options[:port], options[:community], "1.3.6.1.2.1.2.2.1.10.#{idx}", options[:timeout])
_st_out, out_octets = query_oid(options[:host], options[:port], options[:community], "1.3.6.1.2.1.2.2.1.16.#{idx}", options[:timeout])

port_name = descr.to_s.strip.presence || "Port #{idx}"
oper_val = oper_status.to_i
in_bytes = in_octets.to_i
out_bytes = out_octets.to_i

perfdata = "in_octets=#{in_bytes}B;out_octets=#{out_bytes}B"

if oper_val == 1
  puts "INTERFACE OK - Port #{port_name} (index #{idx}) is UP | #{perfdata}"
  exit 0
elsif oper_val == 2
  puts "INTERFACE CRITICAL - Port #{port_name} (index #{idx}) is DOWN | #{perfdata}"
  exit 2
else
  puts "INTERFACE WARNING - Port #{port_name} (index #{idx}) status is UNKNOWN (#{oper_val}) | #{perfdata}"
  exit 1
end
