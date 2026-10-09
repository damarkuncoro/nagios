require 'rails_helper'

RSpec.describe Statuses::UseCases::FetchServicegroups do
  describe '.call' do
    it 'groups services by functional category' do
      mock_service1 = Statuses::Entities::ServiceStatus.new(host_name: 'host1', description: 'HTTP', status: 2)
      mock_service2 = Statuses::Entities::ServiceStatus.new(host_name: 'host1', description: 'Root Partition', status: 2)

      allow(Engines::NagiosEngine).to receive(:services).and_return([mock_service1, mock_service2])

      groups = described_class.call

      expect(groups.size).to eq(2)
      expect(groups.map { |g| g[:name] }).to include('Web Services', 'Storage & Disk Services')
    end
  end
end
