# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::AlertSummaryAggregator do
  let(:aggregator) { described_class.new }

  describe '#analyze' do
    context 'with empty alerts' do
      it 'returns zero totals and empty top producers' do
        result = aggregator.analyze([])

        expect(result.totals.total).to eq(0)
        expect(result.top_hosts).to be_empty
        expect(result.top_services).to be_empty
      end
    end

    context 'with mixed host and service alerts' do
      let(:alerts) do
        [
          { host_name: 'srv01', service_description: 'HTTP', state: 'CRITICAL', state_type: 'HARD' },
          { host_name: 'srv01', service_description: 'HTTP', state: 'WARNING', state_type: 'SOFT' },
          { host_name: 'srv01', service_description: 'HTTP', state: 'OK', state_type: 'HARD' },
          { host_name: 'srv01', service_description: 'SSH', state: 'CRITICAL', state_type: 'HARD' },
          { host_name: 'srv02', service_description: 'PING', state: 'WARNING', state_type: 'SOFT' },
          { host_name: 'core-router', service_description: '', state: 'DOWN', state_type: 'HARD' }
        ]
      end

      it 'correctly computes totals, HARD vs SOFT, and top producers' do
        result = aggregator.analyze(alerts, limit: 5)

        totals = result.totals
        expect(totals.total).to eq(6)
        expect(totals.host_total).to eq(1) # core-router has no service_desc
        expect(totals.service_total).to eq(5)
        expect(totals.hard_total).to eq(4)
        expect(totals.soft_total).to eq(2)
        expect(totals.recovery_total).to eq(1)
        expect(totals.critical_total).to eq(3) # 2 CRITICAL + 1 DOWN
        expect(totals.warning_total).to eq(2)

        # Top hosts (srv01 has 2 HTTP problems + 1 SSH problem = 3 total problem alerts)
        expect(result.top_hosts.first).to eq(['srv01', 3])

        # Top services (srv01 / HTTP has 2 problem alerts)
        expect(result.top_services.first).to eq(['srv01 / HTTP', 2])

        # Producer details
        top_hp = result.top_host_producers.first
        expect(top_hp.name).to eq('srv01')
        expect(top_hp.critical_count).to eq(2)
        expect(top_hp.warning_count).to eq(1)
        expect(top_hp.recovery_count).to eq(1)
        expect(top_hp.share_pct).to be > 0.0
      end
    end
  end
end
