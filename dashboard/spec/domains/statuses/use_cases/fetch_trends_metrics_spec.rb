require 'rails_helper'

RSpec.describe Statuses::UseCases::FetchTrendsMetrics do
  describe '.call' do
    it 'computes daily trend metrics for 7 days' do
      mock_alerts = [
        { host_name: 'host1', service_description: 'HTTP', state: 'CRITICAL', timestamp: Time.now }
      ]

      allow(Engines::NagiosEngine).to receive(:alerts).and_return(mock_alerts)

      trends = described_class.call(days: 7)

      expect(trends[:days]).to eq(7)
      expect(trends[:daily_stats].size).to eq(7)
    end
  end
end
