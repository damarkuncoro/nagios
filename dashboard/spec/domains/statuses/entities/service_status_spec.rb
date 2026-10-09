require 'rails_helper'

RSpec.describe Statuses::Entities::ServiceStatus do
  describe '#initialize' do
    it 'maps status 2 to OK' do
      service = described_class.new(host_name: 'localhost', description: 'HTTP', status: 2)
      expect(service.status).to eq('OK')
      expect(service.ok?).to be true
      expect(service.warning?).to be false
    end

    it 'maps status 4 to WARNING' do
      service = described_class.new(host_name: 'localhost', description: 'HTTP', status: 4)
      expect(service.status).to eq('WARNING')
      expect(service.warning?).to be true
    end

    it 'maps status 8 to CRITICAL' do
      service = described_class.new(host_name: 'localhost', description: 'HTTP', status: 8)
      expect(service.status).to eq('CRITICAL')
      expect(service.critical?).to be true
    end

    it 'generates a clean parameterize dom_id' do
      service = described_class.new(host_name: 'localhost', description: 'Root Partition', status: 2)
      expect(service.dom_id).to eq('service_localhost_root-partition')
    end
  end

  describe '#to_h' do
    it 'returns Hash representation' do
      service = described_class.new(host_name: 'localhost', description: 'PING', status: 2, plugin_output: 'PING OK')
      hash = service.to_h

      expect(hash[:host_name]).to eq('localhost')
      expect(hash[:description]).to eq('PING')
      expect(hash[:status]).to eq('OK')
      expect(hash[:plugin_output]).to eq('PING OK')
    end
  end
end
