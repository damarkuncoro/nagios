# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::NotificationHistoryManager do
  let(:manager) { described_class.new }
  let(:now) { Time.at(1_700_000_000) }

  let(:notifications) do
    [
      {
        timestamp: now - 300,
        host_name: 'srv-web01',
        service_desc: 'HTTP',
        contact_name: 'alice',
        notification_type: 'SERVICE NOTIFICATION',
        reason: 'PROBLEM',
        state: 'CRITICAL',
        output: 'Connection refused'
      },
      {
        timestamp: now - 180,
        host_name: 'srv-web01',
        service_desc: 'HTTP',
        contact_name: 'alice',
        notification_type: 'SERVICE NOTIFICATION',
        reason: 'RECOVERY',
        state: 'OK',
        output: 'HTTP OK'
      },
      {
        timestamp: now - 60,
        host_name: 'router-gw',
        service_desc: nil,
        contact_name: 'bob',
        notification_type: 'HOST NOTIFICATION',
        reason: 'PROBLEM',
        state: 'DOWN',
        output: 'Packet loss 100%'
      }
    ]
  end

  describe '#filter' do
    it 'filters notifications by contact' do
      res = manager.filter(notifications, contact: 'alice')

      expect(res.size).to eq(2)
      expect(res.all? { |n| n.contact_name == 'alice' }).to be true
    end

    it 'filters notifications by host_name' do
      res = manager.filter(notifications, host_name: 'router-gw')

      expect(res.size).to eq(1)
      expect(res.first.host_name).to eq('router-gw')
    end

    it 'filters by type' do
      res = manager.filter(notifications, type: :host)

      expect(res.size).to eq(1)
      expect(res.first.host_notification?).to be true
    end

    it 'supports keyword queries' do
      res = manager.filter(notifications, query: 'packet loss')

      expect(res.size).to eq(1)
      expect(res.first.host_name).to eq('router-gw')
    end
  end

  describe '#calculate_stats' do
    it 'aggregates delivery statistics and recipient rankings' do
      stats = manager.calculate_stats(notifications)

      expect(stats.total).to eq(3)
      expect(stats.host_total).to eq(1)
      expect(stats.service_total).to eq(2)
      expect(stats.problem_total).to eq(2)
      expect(stats.recovery_total).to eq(1)
      expect(stats.top_contacts).to eq([['alice', 2], ['bob', 1]])
    end
  end

  describe '#export_csv' do
    it 'generates valid CSV with header and data rows' do
      csv = manager.export_csv(notifications)

      lines = csv.split("\n")
      expect(lines.first).to include('Timestamp,Host Name,Service Description,Contact Name')
      expect(lines.size).to eq(4) # header + 3 rows
      expect(lines[1]).to include('srv-web01,HTTP,alice,SERVICE')
      expect(lines[3]).to include('router-gw,HOST ALERT,bob,HOST')
    end
  end
end
