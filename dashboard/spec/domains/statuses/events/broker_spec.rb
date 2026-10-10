require 'rails_helper'

RSpec.describe Statuses::Events::Broker do
  before do
    described_class.clear_callbacks!
    described_class.clear_history!
  end

  after do
    described_class.clear_callbacks!
    described_class.clear_history!
  end

  describe '.publish and .register_callback' do
    it 'dispatches events to registered callbacks for specific event type' do
      received = []
      described_class.register_callback(:acknowledgement) do |event|
        received << event
      end

      published = described_class.publish(:acknowledgement, { host_name: 'srv1' }, source: 'test')

      expect(received.size).to eq(1)
      expect(received.first).to eq(published)
      expect(received.first.type).to eq(:acknowledgement)
      expect(received.first.payload[:host_name]).to eq('srv1')
      expect(received.first.source).to eq('test')
    end

    it 'dispatches events to :all callbacks regardless of event type' do
      all_events = []
      described_class.register_callback(:all) do |event|
        all_events << event
      end

      described_class.publish(:check, { host_name: 'srv1' })
      described_class.publish(:downtime, { host_name: 'srv2' })

      expect(all_events.size).to eq(2)
      expect(all_events.map(&:type)).to eq(%i[check downtime])
    end

    it 'isolates errors in failing subscribers' do
      described_class.register_callback(:check) do |_event|
        raise StandardError, "Boom in subscriber!"
      end

      successful_runs = []
      described_class.register_callback(:check) do |event|
        successful_runs << event
      end

      expect {
        described_class.publish(:check, { host_name: 'srv1' })
      }.not_to raise_error

      expect(successful_runs.size).to eq(1)
    end
  end

  describe '.history' do
    it 'records recent events in reverse order' do
      described_class.publish(:check, { host_name: 'srv1' })
      described_class.publish(:downtime, { host_name: 'srv2' })

      hist = described_class.history
      expect(hist.size).to eq(2)
      expect(hist.first[:type]).to eq(:downtime)
      expect(hist.second[:type]).to eq(:check)
    end
  end
end
