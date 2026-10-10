# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::TacticalOverviewAggregator do
  let(:aggregator) { described_class.new }

  describe '#aggregate' do
    context 'when empty' do
      it 'returns 100% health and zeroes' do
        result = aggregator.aggregate(hosts: [], services: [])

        expect(result.host_health_pct).to eq(100.0)
        expect(result.service_health_pct).to eq(100.0)
        expect(result.cluster_health_pct).to eq(100.0)
        expect(result.total_unhandled_problems).to eq(0)
        expect(result.hosts.total).to eq(0)
        expect(result.services.total).to eq(0)
      end
    end

    context 'with mixed host states' do
      let(:hosts) do
        [
          { name: 'host1', status: 'UP', acknowledged: false },
          { name: 'host2', status: 'UP', acknowledged: false },
          { name: 'host3', status: 'DOWN', acknowledged: false, scheduled_downtime_depth: 0 },
          { name: 'host4', status: 'DOWN', acknowledged: true, scheduled_downtime_depth: 0 },
          { name: 'host5', status: 'DOWN', acknowledged: false, scheduled_downtime_depth: 1 },
          { name: 'host6', status: 'UNREACHABLE', acknowledged: false, scheduled_downtime_depth: 0, is_flapping: true }
        ]
      end

      it 'correctly classifies host health and down categories' do
        result = aggregator.aggregate(hosts: hosts, services: [])

        expect(result.hosts.total).to eq(6)
        expect(result.hosts.up).to eq(2)
        expect(result.hosts.down_unhandled).to eq(1)
        expect(result.hosts.down_ack).to eq(1)
        expect(result.hosts.down_downtime).to eq(1)
        expect(result.hosts.unreachable).to eq(1)
        expect(result.hosts.unreachable_unhandled).to eq(1)
        expect(result.hosts.flapping).to eq(1)
        expect(result.host_health_pct).to eq(33.3)
      end
    end

    context 'with mixed service states' do
      let(:services) do
        [
          { description: 'HTTP', status: 'OK' },
          { description: 'SSH', status: 'OK' },
          { description: 'DISK', status: 'WARNING', acknowledged: false },
          { description: 'MEM', status: 'WARNING', acknowledged: true },
          { description: 'CPU', status: 'CRITICAL', acknowledged: false },
          { description: 'DB', status: 'CRITICAL', scheduled_downtime_depth: 1 },
          { description: 'QUEUE', status: 'UNKNOWN', acknowledged: false },
          { description: 'BACKUP', status: 'PENDING' }
        ]
      end

      it 'correctly classifies service health and unhandled counts' do
        result = aggregator.aggregate(hosts: [], services: services)

        expect(result.services.total).to eq(8)
        expect(result.services.ok).to eq(2)
        expect(result.services.warning_unhandled).to eq(1)
        expect(result.services.warning_ack).to eq(1)
        expect(result.services.critical_unhandled).to eq(1)
        expect(result.services.critical_downtime).to eq(1)
        expect(result.services.unknown_unhandled).to eq(1)
        expect(result.services.pending).to eq(1)
        expect(result.service_health_pct).to eq(25.0)
        # Unhandled: 1 warning + 1 critical + 1 unknown = 3
        expect(result.total_unhandled_problems).to eq(3)
      end
    end

    context 'with both hosts and services' do
      let(:hosts) do
        [
          { name: 'h1', status: 'UP' },
          { name: 'h2', status: 'UP' },
          { name: 'h3', status: 'DOWN', acknowledged: false }
        ]
      end

      let(:services) do
        [
          { description: 's1', status: 'OK' },
          { description: 's2', status: 'CRITICAL', acknowledged: false }
        ]
      end

      it 'computes combined cluster health accurately' do
        result = aggregator.aggregate(hosts: hosts, services: services, program_status: { version: '4.5.12' })

        expect(result.program_status).to eq({ version: '4.5.12' })
        # Hosts: 2/3 (66.7%), Services: 1/2 (50.0%)
        # Combined: (2 + 1) / (3 + 2) = 3/5 = 60.0%
        expect(result.cluster_health_pct).to eq(60.0)
        expect(result.total_unhandled_problems).to eq(2) # 1 host down + 1 service crit
      end
    end
  end
end
