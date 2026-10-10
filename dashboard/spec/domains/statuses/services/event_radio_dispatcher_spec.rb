# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::EventRadioDispatcher do
  let(:dispatcher) { described_class.new }

  before do
    dispatcher.clear!
  end

  describe '#subscribe and #broadcast' do
    it 'delivers messages to channel subscribers' do
      received = []
      sub_id = dispatcher.subscribe(:host_checks) do |msg|
        received << msg
      end

      expect(sub_id).to be_present

      dispatcher.broadcast(:host_checks, { host: 'node-1', state: 'UP' })

      expect(received.size).to eq(1)
      expect(received.first[:channel]).to eq(:host_checks)
      expect(received.first[:payload][:host]).to eq('node-1')
      expect(received.first[:payload][:state]).to eq('UP')
    end

    it 'does not leak messages to different channels' do
      svc_received = []
      dispatcher.subscribe(:service_checks) { |msg| svc_received << msg }

      dispatcher.broadcast(:host_checks, { host: 'node-1' })

      expect(svc_received).to be_empty
    end

    it 'supports unsubscribing cleanly' do
      messages = []
      sub_id = dispatcher.subscribe(:alerts) { |m| messages << m }

      dispatcher.broadcast(:alerts, { text: 'Alert 1' })
      expect(messages.size).to eq(1)

      dispatcher.unsubscribe(:alerts, sub_id)
      dispatcher.broadcast(:alerts, { text: 'Alert 2' })
      expect(messages.size).to eq(1)
    end
  end

  describe '#channel_history' do
    it 'records recent messages in history ring buffer' do
      dispatcher.broadcast(:state_changes, { item: 1 })
      dispatcher.broadcast(:state_changes, { item: 2 })

      history = dispatcher.channel_history(:state_changes)
      expect(history.size).to eq(2)
      expect(history.first[:payload][:item]).to eq(2)
    end
  end

  describe '#stats' do
    it 'reports subscriber counts across channels' do
      dispatcher.subscribe(:host_checks) {}
      dispatcher.subscribe(:host_checks) {}
      dispatcher.subscribe(:service_checks) {}

      stats = dispatcher.stats
      expect(stats[:total_subscribers]).to eq(3)
      expect(stats[:subscriber_counts][:host_checks]).to eq(2)
      expect(stats[:subscriber_counts][:service_checks]).to eq(1)
    end
  end
end
