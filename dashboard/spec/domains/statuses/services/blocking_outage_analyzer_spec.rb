# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::BlockingOutageAnalyzer do
  let(:analyzer) { described_class.new(severity_divisor: 4) }

  describe '#analyze' do
    context 'when no outages exist' do
      let(:hosts) { [{ name: 'web01', status: 'UP' }, { name: 'db01', status: 'UP' }] }
      let(:services) { [{ host_name: 'web01', description: 'HTTP' }] }

      it 'returns 100% health and zero outages' do
        result = analyzer.analyze(hosts: hosts, services: services)

        expect(result.total_blocking_outages).to eq(0)
        expect(result.outages).to be_empty
        expect(result.network_health_pct).to eq(100.0)
      end
    end

    context 'with standalone host failure' do
      let(:hosts) { [{ name: 'srv01', status: 'DOWN', parents: [] }] }
      let(:services) do
        [
          { host_name: 'srv01', description: 'PING' },
          { host_name: 'srv01', description: 'SSH' },
          { host_name: 'srv01', description: 'HTTP' },
          { host_name: 'srv01', description: 'APP' }
        ]
      end

      it 'identifies host as root blocker with weighted severity' do
        result = analyzer.analyze(hosts: hosts, services: services)

        expect(result.total_blocking_outages).to eq(1)
        outage = result.outages.first
        expect(outage.host_name).to eq('srv01')
        expect(outage.root_cause?).to be true
        expect(outage.affected_child_hosts).to eq(1)
        expect(outage.affected_child_services).to eq(4)
        # Severity = 1 host + (4 services / 4) = 2
        expect(outage.severity).to eq(2)
      end
    end

    context 'with hierarchical cascading network outage' do
      let(:hosts) do
        [
          { name: 'core-router', status: 'DOWN', parents: [] },
          { name: 'dist-switch', status: 'UNREACHABLE', parents: ['core-router'] },
          { name: 'edge-server', status: 'UNREACHABLE', parents: ['dist-switch'] },
          { name: 'independent-host', status: 'UP', parents: [] }
        ]
      end

      let(:services) do
        [
          { host_name: 'core-router', description: 'BGP' },
          { host_name: 'dist-switch', description: 'SNMP' },
          { host_name: 'edge-server', description: 'HTTP' },
          { host_name: 'edge-server', description: 'HTTPS' }
        ]
      end

      it 'correctly determines root cause and sorts by severity' do
        result = analyzer.analyze(hosts: hosts, services: services)

        expect(result.total_blocking_outages).to eq(1)
        expect(result.outages.size).to eq(3)

        root = result.outages.first
        expect(root.host_name).to eq('core-router')
        expect(root.root_cause?).to be true
        expect(root.affected_child_hosts).to eq(3)
        expect(root.affected_child_services).to eq(4)
        # Severity = 3 hosts + (4 svcs / 4) = 4
        expect(root.severity).to eq(4)

        downstream = result.outages.find { |o| o.host_name == 'dist-switch' }
        expect(downstream.root_cause?).to be false
        expect(downstream.blocking_parents).to eq(['core-router'])
      end
    end

    context 'with multiple independent root blockers' do
      let(:hosts) do
        [
          { name: 'router-east', status: 'DOWN', parents: [] },
          { name: 'srv-east', status: 'UNREACHABLE', parents: ['router-east'] },
          { name: 'router-west', status: 'DOWN', parents: [] }
        ]
      end

      let(:services) do
        [
          { host_name: 'router-east', description: 'PING' },
          { host_name: 'srv-east', description: 'HTTP' },
          { host_name: 'router-west', description: 'PING' }
        ]
      end

      it 'counts multiple root blockers' do
        result = analyzer.analyze(hosts: hosts, services: services)

        expect(result.total_blocking_outages).to eq(2)
        root_names = result.outages.select(&:root_cause?).map(&:host_name)
        expect(root_names).to contain_exactly('router-east', 'router-west')
      end
    end
  end
end
