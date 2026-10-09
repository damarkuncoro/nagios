require 'rails_helper'

RSpec.describe Statuses::UseCases::FetchIncidentSummary do
  describe '.call' do
    it 'aggregates alert totals and top problematic hosts and services' do
      mock_alerts = [
        { host_name: 'host1', service_description: 'HTTP', state: 'CRITICAL' },
        { host_name: 'host1', service_description: 'HTTP', state: 'CRITICAL' },
        { host_name: 'host2', service_description: 'PING', state: 'WARNING' }
      ]

      allow(Engines::NagiosEngine).to receive(:alerts).and_return(mock_alerts)

      summary = described_class.call

      expect(summary[:total_alerts]).to eq(3)
      expect(summary[:top_hosts].first).to eq(['host1', 2])
      expect(summary[:top_services].first).to eq(['host1 / HTTP', 2])
    end
  end
end
