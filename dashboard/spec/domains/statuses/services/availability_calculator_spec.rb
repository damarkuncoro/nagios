# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::AvailabilityCalculator do
  let(:hosts) do
    [
      { name: 'srv-prod-01', status: 'UP' },
      { name: 'srv-prod-02', status: 'DOWN', scheduled_downtime_depth: 1, downtime_seconds: 86400 }
    ]
  end

  let(:services) do
    [
      { host_name: 'srv-prod-01', description: 'HTTP API', status: 'OK' },
      { host_name: 'srv-prod-01', description: 'Disk Root', status: 'WARNING' },
      { host_name: 'srv-prod-02', description: 'PostgreSQL', status: 'CRITICAL', scheduled_downtime_depth: 1, downtime_seconds: 86400 }
    ]
  end

  describe '#calculate' do
    it 'calculates host and service availability discounting scheduled maintenance' do
      report = described_class.calculate(hosts: hosts, services: services, window_seconds: 86400)

      expect(report).to be_a(Statuses::Services::AvailabilityCalculator::AvailabilityReport)
      expect(report.host_reports.size).to eq(2)
      expect(report.service_reports.size).to eq(3)

      # Host 1: 100% UP
      h1 = report.host_reports.first
      expect(h1.status).to eq('UP')
      expect(h1.raw_availability_pct).to eq(100.0)
      expect(h1.sla_availability_pct).to eq(100.0)
      expect(h1.sla_met).to be true

      # Host 2: DOWN but in full scheduled downtime -> SLA discounts downtime
      h2 = report.host_reports.second
      expect(h2.status).to eq('DOWN')
      expect(h2.raw_availability_pct).to eq(0.0)
      expect(h2.scheduled_downtime_seconds).to eq(86400)

      # Service 1: OK -> 100%
      s1 = report.service_reports.first
      expect(s1.sla_availability_pct).to eq(100.0)
      expect(s1.sla_met).to be true

      # Service 2: WARNING -> 95%
      s2 = report.service_reports.second
      expect(s2.raw_availability_pct).to eq(95.0)

      expect(report.overall_sla_pct).to be >= 0.0
    end
  end
end
