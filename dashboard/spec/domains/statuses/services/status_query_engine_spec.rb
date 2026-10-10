# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::StatusQueryEngine do
  let(:engine) { described_class.new }

  describe '#filter_hosts' do
    let(:hosts) do
      [
        { name: 'web01', status: 'UP', acknowledged: false, is_flapping: false },
        { name: 'web02', status: 'DOWN', acknowledged: false, scheduled_downtime_depth: 0 },
        { name: 'web03', status: 'DOWN', acknowledged: true, scheduled_downtime_depth: 0 },
        { name: 'web04', status: 'DOWN', acknowledged: false, scheduled_downtime_depth: 1 },
        { name: 'db01', status: 'UNREACHABLE', acknowledged: false, is_flapping: true }
      ]
    end

    it 'isolates unhandled problems (suppresses ACK and scheduled downtime)' do
      result = engine.filter_hosts(hosts, unhandled_only: true)

      names = result.items.map { |h| h[:name] }
      expect(names).to contain_exactly('web02', 'db01')
      expect(result.filtered_count).to eq(2)
      expect(result.total_count).to eq(5)
    end

    it 'filters flapping hosts' do
      result = engine.filter_hosts(hosts, flapping: true)

      expect(result.items.map { |h| h[:name] }).to eq(['db01'])
    end

    it 'supports keyword queries and sorting' do
      result = engine.filter_hosts(hosts, query: 'web', sort_by: 'name', sort_order: :desc)

      names = result.items.map { |h| h[:name] }
      expect(names).to eq(%w[web04 web03 web02 web01])
    end

    it 'calculates host totals accurately' do
      totals = engine.calculate_host_totals(hosts)

      expect(totals.total).to eq(5)
      expect(totals.up).to eq(1)
      expect(totals.down).to eq(3)
      expect(totals.down_unhandled).to eq(1)
      expect(totals.down_ack).to eq(1)
      expect(totals.down_downtime).to eq(1)
      expect(totals.unreachable_unhandled).to eq(1)
      expect(totals.flapping).to eq(1)
    end
  end

  describe '#filter_services' do
    let(:services) do
      [
        { host_name: 'srv01', description: 'HTTP', status: 'OK' },
        { host_name: 'srv01', description: 'SSH', status: 'WARNING', acknowledged: false },
        { host_name: 'srv01', description: 'DISK', status: 'CRITICAL', acknowledged: true },
        { host_name: 'srv02', description: 'MEM', status: 'CRITICAL', scheduled_downtime_depth: 1 },
        { host_name: 'srv02', description: 'APP', status: 'UNKNOWN', acknowledged: false }
      ]
    end

    it 'isolates unhandled service problems' do
      result = engine.filter_services(services, unhandled_only: true)

      descriptions = result.items.map { |s| s[:description] }
      expect(descriptions).to contain_exactly('SSH', 'APP')
    end

    it 'filters by host_name' do
      result = engine.filter_services(services, host_name: 'srv01')

      expect(result.items.size).to eq(3)
    end

    it 'calculates service totals accurately' do
      totals = engine.calculate_service_totals(services)

      expect(totals.total).to eq(5)
      expect(totals.ok).to eq(1)
      expect(totals.warning).to eq(1)
      expect(totals.warning_unhandled).to eq(1)
      expect(totals.critical).to eq(2)
      expect(totals.critical_ack).to eq(1)
      expect(totals.critical_downtime).to eq(1)
      expect(totals.unknown_unhandled).to eq(1)
    end
  end
end
