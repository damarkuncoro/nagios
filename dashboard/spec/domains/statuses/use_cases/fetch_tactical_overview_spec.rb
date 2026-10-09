require 'rails_helper'

RSpec.describe Statuses::UseCases::FetchTacticalOverview do
  describe '.call' do
    it 'computes health percentages and breakdown grids' do
      mock_host = Statuses::Entities::HostStatus.new(name: 'host1', status: 2)
      mock_service1 = Statuses::Entities::ServiceStatus.new(host_name: 'host1', description: 'HTTP', status: 2)
      mock_service2 = Statuses::Entities::ServiceStatus.new(host_name: 'host1', description: 'PING', status: 4, acknowledged: true)

      allow(Engines::NagiosEngine).to receive(:hosts).and_return([mock_host])
      allow(Engines::NagiosEngine).to receive(:services).and_return([mock_service1, mock_service2])
      allow(Engines::NagiosEngine).to receive(:program_status).and_return({ version: '4.5.12' })

      tac = described_class.call

      expect(tac[:host_health_pct]).to eq(100.0)
      expect(tac[:service_health_pct]).to eq(50.0)
      expect(tac[:services][:warning_ack]).to eq(1)
      expect(tac[:services][:warning_unhandled]).to eq(0)
    end
  end
end
