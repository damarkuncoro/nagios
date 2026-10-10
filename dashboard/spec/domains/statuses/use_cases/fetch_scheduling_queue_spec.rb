# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::UseCases::FetchSchedulingQueue do
  let(:mock_engine) { class_double(Engines::NagiosEngine) }
  let(:base_time) { Time.zone.parse('2026-10-10 12:00:00') }

  let(:mock_host) do
    double(
      name: 'router-core',
      status: 'UP',
      next_check: base_time + 30.seconds,
      current_attempt: 1,
      max_attempts: 3
    )
  end

  let(:mock_service_soon) do
    double(
      host_name: 'router-core',
      description: 'BGP Status',
      status: 'OK',
      next_check: base_time + 45.seconds,
      latency: 0.05,
      attempts: '1/3'
    )
  end

  let(:mock_service_later) do
    double(
      host_name: 'router-core',
      description: 'Interface eth0',
      status: 'OK',
      next_check: base_time + 400.seconds,
      latency: 0.01,
      attempts: '1/3'
    )
  end

  before do
    allow(mock_engine).to receive(:hosts).and_return([mock_host])
    allow(mock_engine).to receive(:services).and_return([mock_service_soon, mock_service_later])
  end

  describe '.call' do
    it 'returns sorted unified items and calculates spread metrics' do
      result = described_class.call(engine: mock_engine, now: base_time)

      expect(result[:items].size).to eq(3)
      # Order should be chronological: +30s (host), +45s (service), +400s (service)
      expect(result[:items].first[:type]).to eq(:host_check)
      expect(result[:items].first[:host_name]).to eq('router-core')
      expect(result[:items].second[:description]).to eq('BGP Status')
      expect(result[:items].third[:description]).to eq('Interface eth0')

      metrics = result[:metrics]
      expect(metrics[:total]).to eq(3)
      expect(metrics[:host_checks]).to eq(1)
      expect(metrics[:service_checks]).to eq(2)
      expect(metrics[:due_in_1m]).to eq(2) # 30s and 45s
      expect(metrics[:due_in_15m]).to eq(1) # 400s
      expect(metrics[:due_in_5m]).to eq(0)
    end

    context 'with filter: "host"' do
      it 'returns only host check items' do
        result = described_class.call(engine: mock_engine, filter: 'host', now: base_time)

        expect(result[:items].size).to eq(1)
        expect(result[:items].first[:type]).to eq(:host_check)
        expect(result[:metrics][:total]).to eq(3) # total metrics reflect all items
      end
    end

    context 'with filter: "service"' do
      it 'returns only service check items' do
        result = described_class.call(engine: mock_engine, filter: 'service', now: base_time)

        expect(result[:items].size).to eq(2)
        expect(result[:items].all? { |i| i[:type] == :service_check }).to be true
      end
    end
  end
end
