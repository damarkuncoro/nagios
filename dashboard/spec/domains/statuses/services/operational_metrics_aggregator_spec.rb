# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::OperationalMetricsAggregator do
  let(:sample_hosts) do
    [
      { name: 'srv-1', status: 0, latency: 0.05, execution_time: 0.12, flapping: false, scheduled_downtime_depth: 0 },
      { name: 'srv-2', status: 0, latency: 0.08, execution_time: 0.15, flapping: false, scheduled_downtime_depth: 0 },
      { name: 'srv-3', status: 1, latency: 0.20, execution_time: 0.50, flapping: true, acknowledged: true, scheduled_downtime_depth: 0 }
    ]
  end

  let(:sample_services) do
    [
      { description: 'HTTP', status: 0, latency: 0.02, execution_time: 0.05, flapping: false },
      { description: 'SSH', status: 0, latency: 0.03, execution_time: 0.04, flapping: false },
      { description: 'DB Port', status: 2, latency: 0.15, execution_time: 0.80, flapping: false, scheduled_downtime_depth: 1 }
    ]
  end

  describe '.aggregate' do
    it 'aggregates host metrics accurately' do
      summary = described_class.aggregate(hosts: sample_hosts, services: sample_services)

      expect(summary.hosts[:total]).to eq(3)
      expect(summary.hosts[:up]).to eq(2)
      expect(summary.hosts[:down]).to eq(1)
      expect(summary.hosts[:acknowledged]).to eq(1)
      expect(summary.hosts[:flapping]).to eq(1)
    end

    it 'aggregates service metrics accurately' do
      summary = described_class.aggregate(hosts: sample_hosts, services: sample_services)

      expect(summary.services[:total]).to eq(3)
      expect(summary.services[:ok]).to eq(2)
      expect(summary.services[:critical]).to eq(1)
      expect(summary.services[:in_downtime]).to eq(1)
    end

    it 'calculates latency and execution time bounds and averages' do
      summary = described_class.aggregate(hosts: sample_hosts, services: sample_services)

      expect(summary.latency[:min]).to eq(0.02)
      expect(summary.latency[:max]).to eq(0.20)
      expect(summary.latency[:avg]).to be > 0.0

      expect(summary.execution_time[:min]).to eq(0.04)
      expect(summary.execution_time[:max]).to eq(0.80)
    end

    it 'computes overall cluster health percentage' do
      # 2 hosts UP out of 3, 2 services OK out of 3 -> 4 healthy out of 6 -> 66.7%
      summary = described_class.aggregate(hosts: sample_hosts, services: sample_services)
      expect(summary.health_percentage).to eq(66.7)
      expect(summary.total_objects).to eq(6)
      expect(summary.flapping_objects).to eq(1)
      expect(summary.downtime_objects).to eq(1)
    end
  end
end
