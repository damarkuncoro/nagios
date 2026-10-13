# frozen_string_literal: true

require 'socket'
require 'openssl'
require 'timeout'

module Discovery
  module Services
    # Walks MIB-2 ifTable (1.3.6.1.2.1.2.2.1) to enumerate router/switch network interfaces.
    class SnmpInterfaceWalker
      InterfaceInfo = Struct.new(
        :index, :name, :status, :in_octets, :out_octets, :speed_mbps,
        keyword_init: true
      )

      def self.walk(host, community: 'public', timeout: 1.0, max_ports: 24)
        new(host, community: community, timeout: timeout, max_ports: max_ports).walk
      end

      def initialize(host, community: 'public', timeout: 1.0, max_ports: 24)
        @host = host
        @community = community
        @timeout = timeout
        @max_ports = max_ports
      end

      def walk
        interfaces = []
        sock = UDPSocket.new
        sock.connect(@host, 161)

        # 1. Query ifNumber (total interfaces)
        if_count = query_single_oid(sock, '1.3.6.1.2.1.2.1.0')&.to_i || 4
        ports_to_check = [if_count, @max_ports].min
        ports_to_check = 8 if ports_to_check <= 0

        # 2. Iterate interfaces up to limit
        (1..ports_to_check).each do |idx|
          descr = query_single_oid(sock, "1.3.6.1.2.1.2.2.1.2.#{idx}")
          next if descr.blank? || descr.to_s.include?('No such')

          oper_status = query_single_oid(sock, "1.3.6.1.2.1.2.2.1.8.#{idx}").to_i
          in_octets = query_single_oid(sock, "1.3.6.1.2.1.2.2.1.10.#{idx}").to_i
          out_octets = query_single_oid(sock, "1.3.6.1.2.1.2.2.1.16.#{idx}").to_i
          raw_speed = query_single_oid(sock, "1.3.6.1.2.1.2.2.1.5.#{idx}").to_i

          interfaces << InterfaceInfo.new(
            index: idx,
            name: descr.to_s.strip,
            status: oper_status == 1 ? 'UP' : 'DOWN',
            in_octets: in_octets,
            out_octets: out_octets,
            speed_mbps: raw_speed > 0 ? (raw_speed / 1_000_000).round : 1000
          )
        end

        sock.close
        interfaces
      rescue StandardError
        sock&.close rescue nil
        []
      end

      private

      def query_single_oid(sock, oid)
        req_der = build_get_request(oid, @community)
        sock.send(req_der, 0)

        ready = IO.select([sock], nil, nil, @timeout)
        return nil unless ready

        data, _ = sock.recvfrom(4096)
        decoded = OpenSSL::ASN1.decode(data)
        pdu = decoded.value[2]
        err_status = pdu.value[1].value.to_i
        return nil if err_status != 0

        vb = pdu.value[3].value.first
        return nil unless vb

        val_node = vb.value[1]
        return nil if val_node.is_a?(OpenSSL::ASN1::ASN1Data) && val_node.tag_class == :CONTEXT_SPECIFIC

        raw = val_node.value
        raw.is_a?(OpenSSL::BN) ? raw.to_i : raw
      rescue StandardError
        nil
      end

      def build_get_request(oid, community)
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
    end
  end
end
