# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::CheckSchedulingQueue do
  let(:service) { described_class.new }
  let(:now) { Time.at(1_000_000) }

  describe '#build_queue' do
    let(:hosts) do
      [
        { name: 'alpha', next_check: now + 30, last_check: now - 300, status: 'UP', current_attempt: 1, max_attempts: 3 },
        { name: 'beta', next_check: now + 120, last_check: now - 180, status: 'DOWN', current_attempt: 2, max_attempts: 3 },
        { name: 'gamma', next_check: nil } # Not scheduled
      ]
    end

    let(:services) do
      [
        { host_name: 'alpha', description: 'HTTP', next_check: now + 10, status: 'OK', latency: 0.12 },
        { host_name: 'alpha', description: 'SSH', next_check: now + 400, status: 'OK', latency: 0.05 },
        { host_name: 'beta', description: 'PING', next_check: now + 600, status: 'CRITICAL', latency: 0.25 }
      ]
    end

    it 'unifies scheduled host and service checks sorted by next_check ascending' do
      result = service.build_queue(hosts: hosts, services: services, now: now)

      expect(result[:items].size).to eq(5) # 2 hosts + 3 services (gamma excluded)
      expect(result[:items].first.description).to eq('HTTP')
      expect(result[:items].first.service_check?).to be true
      expect(result[:items][1].host_name).to eq('alpha')
      expect(result[:items][1].host_check?).to be true

      metrics = result[:metrics]
      expect(metrics.total).to eq(5)
      expect(metrics.host_checks).to eq(2)
      expect(metrics.service_checks).to eq(3)
      # due_in_1m: HTTP (+10s), alpha (+30s) = 2
      expect(metrics.due_in_1m).to eq(2)
      # due_in_5m: beta (+120s) = 1
      expect(metrics.due_in_5m).to eq(1)
      # due_in_15m: SSH (+400s), PING (+600s) = 2
      expect(metrics.due_in_15m).to eq(2)
      expect(metrics.check_storm_detected).to be false
    end

    it 'filters items by host check type' do
      result = service.build_queue(hosts: hosts, services: services, filter: 'host', now: now)

      expect(result[:items].size).to eq(2)
      expect(result[:items].all?(&:host_check?)).to be true
    end

    it 'filters items by service check type' do
      result = service.build_queue(hosts: hosts, services: services, filter: 'service', now: now)

      expect(result[:items].size).to eq(3)
      expect(result[:items].all?(&:service_check?)).to be true
    end

    it 'supports sorting by host name descending' do
      result = service.build_queue(hosts: hosts, services: services, sort_by: 'hostname', sort_order: :desc, now: now)

      names = result[:items].map(&:host_name)
      expect(names.first).to eq('beta')
    end

    it 'detects check storms when more than 25 checks are due within 1 minute' do
      storm_services = (1..30).map do |i|
        { host_name: "host-#{i}", description: 'PING', next_check: now + (i % 50), status: 'OK' }
      end

      result = service.build_queue(hosts: [], services: storm_services, now: now)
      expect(result[:metrics].due_in_1m).to eq(30)
      expect(result[:metrics].check_storm_detected).to be true
    end
  end
end
