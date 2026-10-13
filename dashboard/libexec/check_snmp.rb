#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# Pure-Ruby Nagios Plugin: check_snmp
# Standard Nagios Plugin API (0=OK, 1=WARNING, 2=CRITICAL, 3=UNKNOWN)
# Pure-Ruby SNMP v1 / v2c Client via OpenSSL::ASN1 & UDPSocket
# ==============================================================================

require 'optparse'
require 'socket'
require 'openssl'
require 'timeout'

options = {
  host: '127.0.0.1',
  port: 161,
  community: 'public',
  oid: '1.3.6.1.2.1.1.1.0',
  protocol: '2c',
  warn: nil,
  crit: nil,
  timeout: 5,
  units: '',
  regex: nil,
  string: nil
}

OptionParser.new do |opts|
  opts.banner = 'Usage: check_snmp -H <host> -o <oid> [options]'

  opts.on('-H', '--host HOST', 'SNMP agent host address (default: 127.0.0.1)') { |v| options[:host] = v }
  opts.on('-p', '--port PORT', Integer, 'SNMP UDP port (default: 161)') { |v| options[:port] = v }
  opts.on('-C', '--community COMMUNITY', 'SNMP community string (default: public)') { |v| options[:community] = v }
  opts.on('-o', '--oid OID', 'Object Identifier (e.g. 1.3.6.1.2.1.1.1.0)') { |v| options[:oid] = v }
  opts.on('-P', '--protocol VERSION', 'SNMP version (1 or 2c, default: 2c)') { |v| options[:protocol] = v }
  opts.on('-w', '--warn THRESHOLD', 'Warning threshold (numeric or range)') { |v| options[:warn] = v }
  opts.on('-c', '--crit THRESHOLD', 'Critical threshold (numeric or range)') { |v| options[:crit] = v }
  opts.on('-t', '--timeout SECONDS', Integer, 'Timeout in seconds (default: 5)') { |v| options[:timeout] = v }
  opts.on('-u', '--units UNITS', 'Unit label for performance data') { |v| options[:units] = v }
  opts.on('-r', '--regex PATTERN', 'Regular expression to match against result') { |v| options[:regex] = Regexp.new(v) }
  opts.on('-s', '--string STRING', 'String expected in result') { |v| options[:string] = v }
  opts.on('-h', '--help', 'Display this help message and exit') do
    puts opts
    exit 3
  end
end.parse!

def build_snmp_request(oid, community, version_str)
  version = (version_str.to_s.downcase == '1') ? 0 : 1
  clean_oid = oid.to_s.sub(/^\./, '')
  req_id = rand(1000..99_999)

  varbind = OpenSSL::ASN1::Sequence.new([
    OpenSSL::ASN1::ObjectId.new(clean_oid),
    OpenSSL::ASN1::Null.new(nil)
  ])
  varbind_list = OpenSSL::ASN1::Sequence.new([varbind])
  pdu = OpenSSL::ASN1::ASN1Data.new([
    OpenSSL::ASN1::Integer.new(req_id),
    OpenSSL::ASN1::Integer.new(0),
    OpenSSL::ASN1::Integer.new(0),
    varbind_list
  ], 0, :CONTEXT_SPECIFIC)

  msg = OpenSSL::ASN1::Sequence.new([
    OpenSSL::ASN1::Integer.new(version),
    OpenSSL::ASN1::OctetString.new(community),
    pdu
  ])
  msg.to_der
end

def parse_snmp_response(der_data)
  decoded = OpenSSL::ASN1.decode(der_data)
  pdu = decoded.value[2]
  err_status = pdu.value[1].value.to_i

  return [:error, "Agent returned error-status #{err_status}"] if err_status != 0

  varbind_list = pdu.value[3]
  vb = varbind_list.value.first
  return [:error, 'No variable binding in response'] unless vb

  val_node = vb.value[1]
  if val_node.is_a?(OpenSSL::ASN1::ASN1Data) && val_node.tag_class == :CONTEXT_SPECIFIC
    return [:error, "No such object or instance (tag #{val_node.tag})"]
  end

  raw_val = val_node.value
  raw_val = raw_val.to_s if raw_val.is_a?(OpenSSL::BN)
  [:ok, raw_val]
rescue StandardError => e
  [:error, "ASN.1 decode error: #{e.message}"]
end

begin
  t_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  sock = UDPSocket.new
  sock.connect(options[:host], options[:port])
  req_der = build_snmp_request(options[:oid], options[:community], options[:protocol])
  sock.send(req_der, 0)

  ready = IO.select([sock], nil, nil, options[:timeout])
  unless ready
    puts "SNMP CRITICAL - No response from #{options[:host]}:#{options[:port]} within #{options[:timeout]}s"
    exit 2
  end

  resp_data, _ = sock.recvfrom(4096)
  sock.close
  t_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  duration = ((t_end - t_start) * 1000.0).round(2)

  status, value = parse_snmp_response(resp_data)
  if status == :error
    puts "SNMP CRITICAL - #{value} for OID #{options[:oid]}"
    exit 2
  end

  # Threshold and pattern evaluation
  val_str = value.to_s.strip
  is_numeric = val_str.match?(/\A-?[0-9]+(\.[0-9]+)?\z/)
  num_val = is_numeric ? val_str.to_f : nil

  perfdata = if is_numeric
               "'#{options[:oid]}'=#{val_str}#{options[:units]};#{options[:warn]};#{options[:crit]};;"
             else
               "time=#{duration}ms"
             end

  # String / Regex match check
  if options[:regex] && !val_str.match?(options[:regex])
    puts "SNMP CRITICAL - Value '#{val_str}' did not match regex #{options[:regex].inspect} | #{perfdata}"
    exit 2
  elsif options[:string] && !val_str.include?(options[:string])
    puts "SNMP CRITICAL - Value '#{val_str}' did not contain expected '#{options[:string]}' | #{perfdata}"
    exit 2
  end

  # Numeric threshold check
  if is_numeric
    crit_val = options[:crit] ? options[:crit].to_f : nil
    warn_val = options[:warn] ? options[:warn].to_f : nil

    if crit_val && num_val >= crit_val
      puts "SNMP CRITICAL - #{val_str} #{options[:units]} exceeded critical threshold (#{crit_val}) | #{perfdata}"
      exit 2
    elsif warn_val && num_val >= warn_val
      puts "SNMP WARNING - #{val_str} #{options[:units]} exceeded warning threshold (#{warn_val}) | #{perfdata}"
      exit 1
    end
  end

  puts "SNMP OK - #{val_str} #{options[:units]}| #{perfdata}"
  exit 0
rescue StandardError => e
  puts "SNMP CRITICAL - Connection failed: #{e.message}"
  exit 2
end
