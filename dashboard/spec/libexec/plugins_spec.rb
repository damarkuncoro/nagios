# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Pure-Ruby Nagios Plugins' do
  let(:libexec_dir) { Rails.root.join('libexec') }

  describe 'check_disk.rb' do
    it 'executes and reports disk usage with valid Nagios exit code' do
      output = `#{libexec_dir}/check_disk.rb -p / -w 99 -c 100`
      exit_code = $?.exitstatus

      expect(exit_code).to eq(0)
      expect(output).to match(/DISK OK - .* free \(.*% used\) on \//)
      expect(output).to include('used=')
      expect(output).to include('free=')
    end
  end

  describe 'check_memory.rb' do
    it 'executes and reports memory usage with perfdata' do
      output = `#{libexec_dir}/check_memory.rb -w 99 -c 100`
      exit_code = $?.exitstatus

      expect(exit_code).to eq(0)
      expect(output).to match(/MEMORY OK - \d+% used/)
      expect(output).to include('used=')
      expect(output).to include('free=')
    end
  end

  describe 'check_tcp.rb' do
    it 'reports CRITICAL when port is closed or invalid host' do
      output = `#{libexec_dir}/check_tcp.rb -H 127.0.0.1 -p 59999 -c 0.5 2>/dev/null`
      exit_code = $?.exitstatus

      expect(exit_code).to eq(2)
      expect(output).to match(/TCP CRITICAL/)
    end
  end

  describe 'check_load.rb' do
    it 'executes and reports system load average with perfdata' do
      output = `#{libexec_dir}/check_load.rb -w 50,50,50 -c 100,100,100`
      exit_code = $?.exitstatus

      expect(exit_code).to eq(0)
      expect(output).to match(/LOAD OK - load average:/)
      expect(output).to include('load1=')
      expect(output).to include('load5=')
      expect(output).to include('load15=')
    end

    it 'returns CRITICAL when load exceeds critical threshold' do
      output = `#{libexec_dir}/check_load.rb -w 0.001,0.001,0.001 -c 0.002,0.002,0.002`
      exit_code = $?.exitstatus

      expect(exit_code).to eq(2)
      expect(output).to match(/LOAD CRITICAL/)
    end
  end

  describe 'check_process.rb' do
    it 'reports OK when matching running processes are within range' do
      output = `#{libexec_dir}/check_process.rb -C ruby -w 1:50 -c 1:100`
      exit_code = $?.exitstatus

      expect(exit_code).to eq(0)
      expect(output).to match(/PROCS OK - \d+ processes matching 'ruby'/)
      expect(output).to include('procs=')
    end

    it 'reports CRITICAL when required process count is zero' do
      output = `#{libexec_dir}/check_process.rb -C non_existent_daemon_xyz_999 -w 1:10 -c 1:20`
      exit_code = $?.exitstatus

      expect(exit_code).to eq(2)
      expect(output).to match(/PROCS CRITICAL - 0 processes matching/)
    end
  end

  describe 'check_dns.rb' do
    it 'resolves localhost and returns latency perfdata' do
      output = `#{libexec_dir}/check_dns.rb -H localhost -t 2.0`
      exit_code = $?.exitstatus

      expect(exit_code).to eq(0)
      expect(output).to match(/DNS OK - localhost resolved to .* in .*ms/)
      expect(output).to include('rta=')
    end

    it 'returns CRITICAL for unresolvable host' do
      output = `#{libexec_dir}/check_dns.rb -H non-existent-domain-xyz-404.local -t 1.0 2>/dev/null`
      exit_code = $?.exitstatus

      expect([2, 3]).to include(exit_code)
      expect(output).to match(/DNS (CRITICAL|UNKNOWN)/)
    end
  end

  describe 'check_ssl_cert.rb' do
    it 'reports CRITICAL when port is closed' do
      output = `#{libexec_dir}/check_ssl_cert.rb -H 127.0.0.1 -p 59998 -t 1.0 2>/dev/null`
      exit_code = $?.exitstatus

      expect(exit_code).to eq(2)
      expect(output).to match(/SSL CRITICAL/)
    end
  end

  describe 'check_ping.rb' do
    it 'executes and reports ping latency and packet loss with perfdata' do
      output = `#{libexec_dir}/check_ping.rb -H 127.0.0.1 -w 100.0,20% -c 500.0,60%`
      exit_code = $?.exitstatus

      expect(exit_code).to eq(0)
      expect(output).to match(/PING OK - Packet loss = \d+%, RTA = \d+\.\d+ ms/)
      expect(output).to include('rta=')
      expect(output).to include('pl=')
    end

    it 'reports CRITICAL when host is unreachable or times out' do
      output = `#{libexec_dir}/check_ping.rb -H 192.0.2.1 -w 10.0,10% -c 20.0,20% -t 1 2>/dev/null`
      exit_code = $?.exitstatus

      expect(exit_code).to eq(2)
      expect(output).to match(/PING CRITICAL/)
    end
  end

  describe 'check_snmp.rb' do
    it 'reports CRITICAL when SNMP agent is unreachable or closed' do
      output = `#{libexec_dir}/check_snmp.rb -H 127.0.0.1 -p 59161 -t 1 2>/dev/null`
      exit_code = $?.exitstatus

      expect(exit_code).to eq(2)
      expect(output).to match(/SNMP CRITICAL/)
    end

    it 'queries an SNMP agent successfully and parses output' do
      server = UDPSocket.new
      server.bind('127.0.0.1', 0)
      port = server.addr[1]

      thread = Thread.new do
        req, client = server.recvfrom(2048)
        decoded = OpenSSL::ASN1.decode(req)
        req_id = decoded.value[2].value[0]
        varbind = OpenSSL::ASN1::Sequence.new([
          OpenSSL::ASN1::ObjectId.new('1.3.6.1.2.1.1.1.0'),
          OpenSSL::ASN1::OctetString.new('PureRuby SNMP Daemon')
        ])
        pdu = OpenSSL::ASN1::ASN1Data.new([
          req_id,
          OpenSSL::ASN1::Integer.new(0),
          OpenSSL::ASN1::Integer.new(0),
          OpenSSL::ASN1::Sequence.new([varbind])
        ], 2, :CONTEXT_SPECIFIC)
        msg = OpenSSL::ASN1::Sequence.new([
          OpenSSL::ASN1::Integer.new(1),
          OpenSSL::ASN1::OctetString.new('public'),
          pdu
        ])
        server.send(msg.to_der, 0, client[3], client[1])
        server.close
      end

      output = `#{libexec_dir}/check_snmp.rb -H 127.0.0.1 -p #{port} -o 1.3.6.1.2.1.1.1.0 -t 2`
      exit_code = $?.exitstatus
      thread.join

      expect(exit_code).to eq(0)
      expect(output).to match(/SNMP OK - PureRuby SNMP Daemon/)
    end
  end

  describe 'check_snmp_interface.rb' do
    it 'reports CRITICAL when port is closed' do
      output = `#{libexec_dir}/check_snmp_interface.rb -H 127.0.0.1 -p 59162 -i 1 -t 1 2>/dev/null`
      exit_code = $?.exitstatus

      expect(exit_code).to eq(2)
      expect(output).to match(/INTERFACE CRITICAL/)
    end
  end
end

