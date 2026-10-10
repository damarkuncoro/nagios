# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::NebModuleRegistry do
  let(:registry) { described_class.new }

  before do
    registry.clear!
  end

  describe '#register_module and #dispatch_event' do
    it 'registers an extension module and triggers registered callbacks' do
      captured_payloads = []

      mod = registry.register_module(
        name: 'livestatus',
        version: '1.2.0',
        author: 'MK'
      ) do
        on(:state_change) { |payload| captured_payloads << payload }
      end

      expect(mod.name).to eq('livestatus')
      expect(mod.enabled?).to be true
      expect(registry.modules.size).to eq(1)

      registry.dispatch_event(:state_change, { host: 'node-1', state: 'DOWN' })

      expect(captured_payloads.size).to eq(1)
      expect(captured_payloads.first[:host]).to eq('node-1')
      expect(captured_payloads.first[:state]).to eq('DOWN')
    end

    it 'suppresses callbacks when module is disabled' do
      dispatched = []

      registry.register_module(name: 'stats_exporter') do
        on(:metric) { |p| dispatched << p }
      end

      registry.disable_module('stats_exporter')
      registry.dispatch_event(:metric, { value: 42 })

      expect(dispatched).to be_empty

      registry.enable_module('stats_exporter')
      registry.dispatch_event(:metric, { value: 99 })

      expect(dispatched.size).to eq(1)
      expect(dispatched.first[:value]).to eq(99)
    end
  end
end
