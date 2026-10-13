# frozen_string_literal: true

require 'ipaddr'
require 'socket'
require 'timeout'
require 'openssl'

module Discovery
  module Services
    # Pure-Ruby concurrent network scanner for subnet sweeps and device fingerprinting.
    class NetworkScanner
      COMMON_PORTS = {
        22 => 'SSH',
        53 => 'DNS',
        80 => 'HTTP',
        161 => 'SNMP',
        443 => 'HTTPS',
        8291 => 'Winbox (MikroTik)'
      }.freeze

      DiscoveredDevice = Struct.new(
        :ip, :hostname, :latency_ms, :open_ports, :vendor,
        :device_type, :snmp_descr, keyword_init: true
      )

      def self.scan_cidr(cidr, community: 'public', timeout: 0.5, concurrency: 16)
        new(community: community, timeout: timeout, concurrency: concurrency).scan_cidr(cidr)
      end

      def initialize(community: 'public', timeout: 0.5, concurrency: 16)
        @community = community
        @timeout = timeout
        @concurrency = concurrency
      end

      def scan_cidr(cidr_str)
        ips = parse_ip_range(cidr_str)
        results = []
        mutex = Mutex.new
        queue = Queue.new
        ips.each { |ip| queue << ip }

        threads = Array.new([@concurrency, ips.size].min) do
          Thread.new do
            until queue.empty?
              ip = queue.pop(true) rescue nil
              break unless ip

              device = probe_device(ip)
              if device
                mutex.synchronize { results << device }
              end
            end
          end
        end

        threads.each(&:join)
        results.sort_by { |d| IPAddr.new(d.ip) rescue d.ip }
      end

      def probe_device(ip)
        t_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        open_ports = check_open_ports(ip)
        return nil if open_ports.empty?

        t_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        latency = ((t_end - t_start) * 1000.0).round(2)

        snmp_descr = query_snmp_sysdescr(ip) if open_ports.include?(161)
        http_banner = grab_http_banner(ip) if open_ports.include?(80) || open_ports.include?(443)
        hostname = resolve_hostname(ip)
        vendor, device_type = identify_fingerprint(open_ports, snmp_descr, http_banner)

        DiscoveredDevice.new(
          ip: ip,
          hostname: hostname,
          latency_ms: latency,
          open_ports: open_ports.map { |p| "#{p}/#{COMMON_PORTS[p] || 'TCP'}" },
          vendor: vendor,
          device_type: device_type,
          snmp_descr: snmp_descr
        )
      end

      private

      def parse_ip_range(cidr_str)
        range = IPAddr.new(cidr_str.to_s.strip)
        range.to_range.to_a.map(&:to_s).reject do |ip|
          ip.end_with?('.0') || ip.end_with?('.255')
        end
      rescue IPAddr::Error
        [cidr_str.to_s.strip]
      end

      def check_open_ports(ip)
        ports = []
        [80, 443, 22, 161, 8291, 53].each do |port|
          if port == 161
            ports << 161 if probe_udp_snmp(ip)
          elsif probe_tcp_port(ip, port)
            ports << port
          end
        end
        ports
      end

      def probe_tcp_port(ip, port)
        Timeout.timeout(@timeout) do
          s = Socket.tcp(ip, port, connect_timeout: @timeout)
          s.close
          true
        end
      rescue StandardError
        false
      end

      def grab_http_banner(ip, port = 80)
        Timeout.timeout(@timeout) do
          s = Socket.tcp(ip, port, connect_timeout: @timeout)
          s.write("GET / HTTP/1.0\r\nHost: #{ip}\r\nUser-Agent: NagiosScanner\r\n\r\n")
          banner = s.read_nonblock(1024) rescue ''
          s.close
          banner
        end
      rescue StandardError
        ''
      end

      def probe_udp_snmp(ip)
        sock = UDPSocket.new
        sock.connect(ip, 161)
        req = build_snmp_request('1.3.6.1.2.1.1.1.0', @community)
        sock.send(req, 0)
        ready = IO.select([sock], nil, nil, @timeout)
        sock.close
        !ready.nil?
      rescue StandardError
        false
      end

      def query_snmp_sysdescr(ip)
        sock = UDPSocket.new
        sock.connect(ip, 161)
        req = build_snmp_request('1.3.6.1.2.1.1.1.0', @community)
        sock.send(req, 0)
        ready = IO.select([sock], nil, nil, @timeout)
        return nil unless ready

        data, _ = sock.recvfrom(2048)
        sock.close
        decoded = OpenSSL::ASN1.decode(data)
        decoded.value[2].value[3].value.first.value[1].value.to_s.strip rescue nil
      rescue StandardError
        nil
      end

      def build_snmp_request(oid, community)
        clean_oid = oid.sub(/^\./, '')
        varbind = OpenSSL::ASN1::Sequence.new([
          OpenSSL::ASN1::ObjectId.new(clean_oid),
          OpenSSL::ASN1::Null.new(nil)
        ])
        pdu = OpenSSL::ASN1::ASN1Data.new([
          OpenSSL::ASN1::Integer.new(rand(1000..99_999)),
          OpenSSL::ASN1::Integer.new(0),
          OpenSSL::ASN1::Integer.new(0),
          OpenSSL::ASN1::Sequence.new([varbind])
        ], 0, :CONTEXT_SPECIFIC)
        OpenSSL::ASN1::Sequence.new([
          OpenSSL::ASN1::Integer.new(1), # SNMPv2c
          OpenSSL::ASN1::OctetString.new(community),
          pdu
        ]).to_der
      end

      def identify_fingerprint(ports, snmp_descr, http_banner = '')
        desc = snmp_descr.to_s.downcase
        banner = http_banner.to_s.downcase

        if desc.include?('routeros') || ports.include?(8291) || banner.include?('mikrotik')
          ['MikroTik', 'Router / Gateway']
        elsif banner.include?('ruijie') || banner.include?('reyee') || banner.include?('rehttpd')
          ['Ruijie Networks', 'Wireless Router / AP']
        elsif desc.include?('cisco') || desc.include?('ios software') || banner.include?('cisco')
          ['Cisco Systems', 'Switch / Router']
        elsif desc.include?('edgeswitch') || desc.include?('unifi') || banner.include?('unifi')
          ['Ubiquiti', 'Managed Switch / AP']
        elsif desc.include?('openwrt') || banner.include?('luci') || banner.include?('openwrt')
          ['OpenWrt', 'Open-Source Router']
        elsif desc.include?('linux')
          ['Linux', 'Server / Appliance']
        elsif desc.include?('windows')
          ['Microsoft', 'Windows Server']
        elsif ports.include?(80) || ports.include?(443)
          ['Generic Web', 'Web Device / Controller']
        elsif ports.include?(22)
          ['Generic Network', 'SSH Network Device']
        else
          ['Unknown', 'Network Device']
        end
      end

      def resolve_hostname(ip)
        Addrinfo.getaddrinfo(ip, nil).first&.getnameinfo&.first || ip
      rescue StandardError
        ip
      end
    end
  end
end
