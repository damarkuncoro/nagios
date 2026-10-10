require 'spec_helper'

RSpec.describe 'Statuses CSV Export Use Cases' do
  describe Statuses::UseCases::ExportHostsCsv do
    let(:hosts) do
      [
        {
          name: 'web-server-01',
          status: 'UP',
          checks_enabled: true,
          notifications_enabled: true,
          acknowledged: false,
          last_check: Time.new(2026, 10, 10, 5, 0, 0),
          next_check: Time.new(2026, 10, 10, 5, 5, 0),
          plugin_output: 'PING OK - Packet loss = 0%'
        },
        {
          name: 'db-server-01',
          status: 'DOWN',
          checks_enabled: true,
          notifications_enabled: false,
          acknowledged: true,
          last_check: Time.new(2026, 10, 10, 5, 1, 0),
          next_check: Time.new(2026, 10, 10, 5, 6, 0),
          plugin_output: 'CRITICAL - Socket timeout'
        }
      ]
    end

    it 'generates CSV with headers and host rows' do
      csv = described_class.call(hosts)
      expect(csv).to include('Host Name,Status,Checks Enabled,Notifications Enabled,Acknowledged,Last Check,Next Check,Plugin Output')
      expect(csv).to include('web-server-01,UP,YES,YES,NO,2026-10-10 05:00:00,2026-10-10 05:05:00,PING OK - Packet loss = 0%')
      expect(csv).to include('db-server-01,DOWN,YES,NO,YES,2026-10-10 05:01:00,2026-10-10 05:06:00,CRITICAL - Socket timeout')
    end

    it 'handles empty hosts array' do
      csv = described_class.call([])
      expect(csv).to include('Host Name,Status,Checks Enabled')
      expect(csv.lines.count).to eq(1)
    end
  end

  describe Statuses::UseCases::ExportNotificationsCsv do
    let(:notifications) do
      [
        {
          timestamp: Time.new(2026, 10, 10, 4, 30, 0),
          host_name: 'web-server-01',
          service_desc: 'HTTP Service',
          contact_name: 'nagiosadmin',
          notification_type: 'PROBLEM',
          state: 'CRITICAL',
          output: 'HTTP CRITICAL - Connection refused'
        }
      ]
    end

    it 'generates CSV with headers and notification rows' do
      csv = described_class.call(notifications)
      expect(csv).to include('Timestamp,Host Name,Service Description,Contact Name,Notification Type,State,Output')
      expect(csv).to include('2026-10-10 04:30:00,web-server-01,HTTP Service,nagiosadmin,PROBLEM,CRITICAL,HTTP CRITICAL - Connection refused')
    end
  end
end
