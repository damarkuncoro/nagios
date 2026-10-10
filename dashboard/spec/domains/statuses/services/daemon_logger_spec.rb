# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'

RSpec.describe Statuses::Services::DaemonLogger do
  let(:timestamp) { Time.new(2026, 10, 10, 12, 0, 0) }

  describe '.format_entry' do
    it 'prefixes message with epoch timestamp' do
      formatted = described_class.format_entry('TEST MESSAGE', timestamp: timestamp)
      expect(formatted).to eq("[#{timestamp.to_i}] TEST MESSAGE")
    end
  end

  describe '.log_service_event' do
    it 'formats service alert matching Nagios log specification' do
      line = described_class.log_service_event(
        host: 'web-1',
        service: 'HTTP',
        state: 'CRITICAL',
        state_type: 'HARD',
        attempt: '3/3',
        output: 'Connection refused',
        timestamp: timestamp,
        log_path: nil
      )
      expect(line).to eq("[#{timestamp.to_i}] SERVICE ALERT: web-1;HTTP;CRITICAL;HARD;3/3;Connection refused")
    end
  end

  describe '.log_host_event' do
    it 'formats host alert matching Nagios log specification' do
      line = described_class.log_host_event(
        host: 'db-1',
        state: 'DOWN',
        state_type: 'HARD',
        attempt: '2/2',
        output: 'Ping timeout',
        timestamp: timestamp,
        log_path: nil
      )
      expect(line).to eq("[#{timestamp.to_i}] HOST ALERT: db-1;DOWN;HARD;2/2;Ping timeout")
    end
  end

  describe '.log_notification' do
    it 'formats service notification entry' do
      line = described_class.log_notification(
        type: 'PROBLEM',
        host: 'web-1',
        service: 'HTTP',
        contact: 'admin',
        output: 'Down',
        timestamp: timestamp,
        log_path: nil
      )
      expect(line).to eq("[#{timestamp.to_i}] SERVICE NOTIFICATION: admin;web-1;HTTP;PROBLEM;Down")
    end
  end

  describe '.rotate' do
    it 'rotates log file to archives directory with date suffix' do
      Dir.mktmpdir do |tmp_dir|
        log_file = File.join(tmp_dir, 'nagios.log')
        archive_dir = File.join(tmp_dir, 'archives')

        File.write(log_file, "[#{timestamp.to_i}] NAGIOS CORE STARTED\n")

        rotated = described_class.rotate(
          log_path: log_file,
          archive_dir: archive_dir,
          timestamp: timestamp
        )

        expect(rotated).to be_present
        expect(File.exist?(rotated)).to be true
        expect(File.basename(rotated)).to match(/^nagios-10-10-2026-\d{2}\.log$/)

        # New log file exists and contains rotation entry
        expect(File.exist?(log_file)).to be true
        new_content = File.read(log_file)
        expect(new_content).to include('LOG ROTATION:')
      end
    end
  end
end
