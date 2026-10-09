require 'rails_helper'

RSpec.describe Statuses::UseCases::FetchUnhandledProblems do
  describe '.call' do
    it 'filters unhandled host and service problems' do
      mock_host = Statuses::Entities::HostStatus.new(name: 'host1', status: 4, acknowledged: false)
      mock_service1 = Statuses::Entities::ServiceStatus.new(host_name: 'host1', description: 'HTTP', status: 4, acknowledged: false)
      mock_service2 = Statuses::Entities::ServiceStatus.new(host_name: 'host1', description: 'PING', status: 2, acknowledged: false)

      allow(Engines::NagiosEngine).to receive(:hosts).and_return([mock_host])
      allow(Engines::NagiosEngine).to receive(:services).and_return([mock_service1, mock_service2])

      result = described_class.call

      expect(result[:hosts].size).to eq(1)
      expect(result[:services].size).to eq(1)
      expect(result[:total_unhandled]).to eq(2)
    end
  end
end
