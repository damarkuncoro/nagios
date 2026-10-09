require 'rails_helper'

RSpec.describe Statuses::UseCases::FetchDashboardData do
  describe '.call' do
    it 'aggregates hosts, services, and statistics' do
      mock_host = Statuses::Entities::HostStatus.new(name: 'host1', status: 2)
      mock_service1 = Statuses::Entities::ServiceStatus.new(host_name: 'host1', description: 'HTTP', status: 2)
      mock_service2 = Statuses::Entities::ServiceStatus.new(host_name: 'host1', description: 'PING', status: 4)

      allow(Engines::NagiosEngine).to receive(:hosts).and_return([mock_host])
      allow(Engines::NagiosEngine).to receive(:services).and_return([mock_service1, mock_service2])
      allow(Engines::NagiosEngine).to receive(:program_status).and_return({ version: '4.5.12' })

      result = described_class.call

      expect(result[:hosts].size).to eq(1)
      expect(result[:services].size).to eq(2)
      expect(result[:host_stats]).to eq({ total: 1, up: 1, down: 0, unreachable: 0 })
      expect(result[:service_stats]).to eq({ total: 2, ok: 1, warning: 1, critical: 0, pending: 0 })
    end
  end
end
