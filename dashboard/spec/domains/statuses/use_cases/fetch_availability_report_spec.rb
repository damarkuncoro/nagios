require 'rails_helper'

RSpec.describe Statuses::UseCases::FetchAvailabilityReport do
  describe '.call' do
    it 'computes host and service SLA uptime percentages' do
      mock_host = Statuses::Entities::HostStatus.new(name: 'host1', status: 2)
      mock_service = Statuses::Entities::ServiceStatus.new(host_name: 'host1', description: 'HTTP', status: 2)

      allow(Engines::NagiosEngine).to receive(:hosts).and_return([mock_host])
      allow(Engines::NagiosEngine).to receive(:services).and_return([mock_service])

      report = described_class.call

      expect(report[:overall_sla_pct]).to eq(100.0)
      expect(report[:host_reports].first[:availability_pct]).to eq(100.0)
      expect(report[:host_reports].first[:sla_met]).to be true
    end
  end
end
