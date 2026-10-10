require 'rails_helper'

RSpec.describe Statuses::Entities::HostStatus do
  describe '#initialize' do
    it 'converts numeric status 2 to UP' do
      host = described_class.new(name: 'server1', status: 2)
      expect(host.status).to eq('UP')
      expect(host.up?).to be true
      expect(host.down?).to be false
    end

    it 'converts numeric status 4 to DOWN' do
      host = described_class.new(name: 'server2', status: 4)
      expect(host.status).to eq('DOWN')
      expect(host.down?).to be true
      expect(host.up?).to be false
    end

    it 'converts numeric status 8 to UNREACHABLE' do
      host = described_class.new(name: 'server3', status: 8)
      expect(host.status).to eq('UNREACHABLE')
      expect(host.unreachable?).to be true
    end

    it 'parses millisecond timestamps correctly' do
      time_ms = 1_791_512_845_000
      host = described_class.new(name: 'server1', status: 2, last_check: time_ms)
      expect(host.last_check).to eq(Time.at(time_ms / 1000))
    end

    it 'formats attempts correctly' do
      host = described_class.new(name: 'server1', status: 2, current_attempt: 1, max_attempts: 10)
      expect(host.attempts_formatted).to eq('1/10')
    end

    it 'detects flapping state correctly' do
      host_flapping = described_class.new(name: 'server1', status: 2, is_flapping: true)
      host_stable = described_class.new(name: 'server2', status: 2, is_flapping: false)

      expect(host_flapping.flapping?).to be true
      expect(host_flapping.to_h[:flapping]).to be true
      expect(host_stable.flapping?).to be false
      expect(host_stable.to_h[:flapping]).to be false
    end
  end

  describe '#to_h' do
    it 'returns a serializable Hash' do
      host = described_class.new(name: 'server1', status: 2, plugin_output: 'PING OK')
      hash = host.to_h

      expect(hash[:name]).to eq('server1')
      expect(hash[:status]).to eq('UP')
      expect(hash[:plugin_output]).to eq('PING OK')
    end
  end
end
