# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::ArchiveLogParser do
  let(:sample_logs) do
    <<~LOG
      [1700000000] LOG ROTATION: DAILY
      [1700000010] SERVICE ALERT: web01;HTTP;CRITICAL;HARD;3;HTTP 500 Internal Server Error
      [1700000020] HOST ALERT: db01;DOWN;SOFT;1;Ping timeout
      [1700000030] SERVICE NOTIFICATION: sysadmin;web01;HTTP;CRITICAL;notify-service-by-email;HTTP 500 Error
      [1700000040] HOST DOWNTIME ALERT: db01;STARTED;Scheduled database migration
      [1700000050] SERVICE FLAPPING ALERT: web01;HTTP;STARTED;Service appears to be flapping between states
      [1700000060] EXTERNAL COMMAND: [1700000060] PROCESS_SERVICE_CHECK_RESULT;web01;HTTP;0;OK
    LOG
  end

  describe '#parse' do
    it 'parses all log categories accurately' do
      entries = described_class.parse(sample_logs)

      expect(entries.size).to eq(7)

      # 1. System log rotation
      rot = entries[0]
      expect(rot.category).to eq(:system)
      expect(rot.event_type).to eq('LOG ROTATION')

      # 2. Service alert
      svc_alert = entries[1]
      expect(svc_alert.alert?).to be true
      expect(svc_alert.host_name).to eq('web01')
      expect(svc_alert.service_desc).to eq('HTTP')
      expect(svc_alert.state).to eq('CRITICAL')
      expect(svc_alert.hard_state?).to be true
      expect(svc_alert.attempt).to eq(3)
      expect(svc_alert.message).to eq('HTTP 500 Internal Server Error')

      # 3. Host alert
      host_alert = entries[2]
      expect(host_alert.alert?).to be true
      expect(host_alert.host_name).to eq('db01')
      expect(host_alert.soft_state?).to be true

      # 4. Service notification
      notif = entries[3]
      expect(notif.notification?).to be true
      expect(notif.contact_name).to eq('sysadmin')
      expect(notif.host_name).to eq('web01')

      # 5. Downtime alert
      dt = entries[4]
      expect(dt.downtime?).to be true
      expect(dt.host_name).to eq('db01')

      # 6. Flapping alert
      flap = entries[5]
      expect(flap.flapping?).to be true
      expect(flap.host_name).to eq('web01')

      # 7. External command
      cmd = entries[6]
      expect(cmd.category).to eq(:command)
    end

    it 'filters logs by category and host' do
      filtered = described_class.parse(sample_logs, filter: { category: :alert, host_name: 'web01' })
      expect(filtered.size).to eq(1)
      expect(filtered.first.service_desc).to eq('HTTP')
    end
  end
end
