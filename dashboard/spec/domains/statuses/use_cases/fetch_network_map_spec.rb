require 'rails_helper'

RSpec.describe Statuses::UseCases::FetchNetworkMap do
  describe '.call' do
    it 'fetches network nodes for statusmap' do
      mock_host = Statuses::Entities::HostStatus.new(name: 'host1', status: 2)
      mock_service = Statuses::Entities::ServiceStatus.new(host_name: 'host1', description: 'HTTP', status: 2)

      allow(Engines::NagiosEngine).to receive(:hosts).and_return([mock_host])
      allow(Engines::NagiosEngine).to receive(:services).and_return([mock_service])

      map = described_class.call

      expect(map[:root][:name]).to eq('Nagios Core Master')
      expect(map[:nodes].size).to eq(1)
      expect(map[:nodes].first[:name]).to eq('host1')
      expect(map[:nodes].first[:ok_services]).to eq(1)
    end
  end
end
