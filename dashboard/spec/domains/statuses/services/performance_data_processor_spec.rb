# frozen_string_literal: true

require 'rails_helper'
require 'tempfile'

RSpec.describe Statuses::Services::PerformanceDataProcessor do
  let(:processor) { described_class.new }
  let(:timet) { 1_700_000_000 }

  describe '#format_service' do
    let(:service) do
      {
        host_name: 'db01',
        description: 'PostgreSQL',
        status: 'OK',
        state_type: 'HARD',
        execution_time: 0.082,
        latency: 0.150,
        performance_data: 'connections=42;100;150;0;200'
      }
    end

    it 'expands standard service performance data template' do
      line = processor.format_service(service, timet: timet)

      expect(line).to include('DATATYPE::SERVICEPERFDATA')
      expect(line).to include('TIMET::1700000000')
      expect(line).to include('HOSTNAME::db01')
      expect(line).to include('SERVICEDESC::PostgreSQL')
      expect(line).to include('SERVICESTATE::OK')
      expect(line).to include('SERVICEEXECUTIONTIME::0.082')
      expect(line).to include('SERVICELATENCY::0.150')
      expect(line).to include('SERVICEPERFDATA::connections=42;100;150;0;200')
    end
  end

  describe '#format_host' do
    let(:host) do
      {
        name: 'edge-gw',
        status: 'UP',
        state_type: 'HARD',
        execution_time: 0.015,
        performance_data: 'rta=0.25ms;100;500;0;'
      }
    end

    it 'expands standard host performance data template' do
      line = processor.format_host(host, timet: timet)

      expect(line).to include('DATATYPE::HOSTPERFDATA')
      expect(line).to include('HOSTNAME::edge-gw')
      expect(line).to include('HOSTSTATE::UP')
      expect(line).to include('HOSTPERFDATA::rta=0.25ms;100;500;0;')
    end
  end

  describe '#to_graphite' do
    let(:service) do
      {
        host_name: 'app-node-1',
        description: 'Memory',
        performance_data: 'used=8192MB;12000;15000;0;16384 free=8192MB'
      }
    end

    it 'generates valid Carbon/Graphite plaintext lines' do
      lines = processor.to_graphite(service, prefix: 'nagios.prod', timet: timet)

      expect(lines.size).to eq(2)
      expect(lines[0]).to eq('nagios.prod.services.app_node_1.memory.used 8192 1700000000')
      expect(lines[1]).to eq('nagios.prod.services.app_node_1.memory.free 8192 1700000000')
    end
  end

  describe '#to_prometheus' do
    let(:hosts) { [{ name: 'web01', status: 'UP' }, { name: 'db01', status: 'DOWN' }] }
    let(:services) do
      [
        { host_name: 'web01', description: 'HTTP', performance_data: 'time=0.035s' }
      ]
    end

    it 'formats Prometheus exposition output with gauges and labels' do
      output = processor.to_prometheus(hosts: hosts, services: services)

      expect(output).to include('nagios_service_metric{host="web01",service="HTTP",metric="time",unit="s"} 0.035')
      expect(output).to include('nagios_host_up{host="web01"} 1')
      expect(output).to include('nagios_host_up{host="db01"} 0')
    end
  end

  describe '#rotate_spool' do
    it 'atomically rotates and reads spool file' do
      temp_file = Tempfile.new('nagios_perfdata_spool')
      temp_file.puts("RECORD_1\nRECORD_2\nRECORD_3")
      temp_file.close

      lines = processor.rotate_spool(temp_file.path)
      expect(lines).to eq(%w[RECORD_1 RECORD_2 RECORD_3])
      expect(File.exist?(temp_file.path)).to be false
    end
  end
end
