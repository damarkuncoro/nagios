# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Discovery::Services::NetworkScanner do
  describe '.scan_cidr' do
    it 'scans localhost and returns discovered device information' do
      devices = described_class.scan_cidr('127.0.0.1/32', timeout: 0.3)

      expect(devices).to be_an(Array)
      if devices.any?
        dev = devices.first
        expect(dev.ip).to eq('127.0.0.1')
        expect(dev.latency_ms).to be >= 0
        expect(dev.open_ports).to be_an(Array)
      end
    end

    it 'correctly fingerprints device types based on ports and SNMP' do
      scanner = described_class.new
      dev_vendor, dev_type = scanner.send(:identify_fingerprint, [8291], 'RouterOS v7.1')
      expect(dev_vendor).to eq('MikroTik')
      expect(dev_type).to eq('Router / Gateway')

      cisco_vendor, cisco_type = scanner.send(:identify_fingerprint, [22, 161], 'Cisco IOS Software, C2960')
      expect(cisco_vendor).to eq('Cisco Systems')
      expect(cisco_type).to eq('Switch / Router')

      linux_vendor, _ = scanner.send(:identify_fingerprint, [22, 80], 'Linux ubuntu 5.15')
      expect(linux_vendor).to eq('Linux')
    end
  end
end

RSpec.describe Discovery::Services::DeviceImporter do
  let(:tmp_cfg) { Rails.root.join('tmp/test_discovery.cfg').to_s }

  before { File.write(tmp_cfg, "# test cfg\n") }
  after { File.unlink(tmp_cfg) rescue nil }

  it 'generates valid Nagios host and service definitions' do
    device = {
      ip: '192.168.1.50',
      hostname: 'core-switch-01',
      vendor: 'Cisco Systems',
      device_type: 'Switch / Router',
      snmp_descr: 'Cisco IOS Software',
      open_ports: '161/SNMP, 22/SSH'
    }

    result = described_class.import(device, cfg_path: tmp_cfg)
    expect(result[:success]).to be true
    expect(result[:host_name]).to eq('core-switch-01')

    content = File.read(tmp_cfg)
    expect(content).to include('define host {')
    expect(content).to include('host_name               core-switch-01')
    expect(content).to include('address                 192.168.1.50')
    expect(content).to include('define service {')
    expect(content).to include('service_description     Ping Latency')
    expect(content).to include('service_description     SNMP System Info')
  end
end

RSpec.describe Discovery::Services::SnmpInterfaceWalker do
  it 'handles unreachable hosts gracefully and returns empty array' do
    result = described_class.walk('192.0.2.1', timeout: 0.1)
    expect(result).to eq([])
  end
end
