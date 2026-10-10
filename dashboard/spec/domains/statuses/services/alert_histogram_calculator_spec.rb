# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::AlertHistogramCalculator do
  let(:base_time) { Time.new(2026, 10, 10, 14, 30, 0) }

  let(:alerts) do
    [
      { timestamp: base_time, state: 'CRITICAL', host_name: 'srv-db01', service_description: 'MySQL' },
      { timestamp: base_time, state: 'WARNING', host_name: 'srv-web01', service_description: 'HTTP' },
      { timestamp: base_time + 3600, state: 'RECOVERY', host_name: 'srv-db01', service_description: 'MySQL' }, # 15:30
      { timestamp: base_time - 7200, state: 'CRITICAL', host_name: 'srv-app01', service_description: 'API' }   # 12:30
    ]
  end

  describe '#analyze' do
    it 'computes 24-hour slots and identifies peak hour' do
      report = described_class.analyze(alerts)

      expect(report).to be_a(Statuses::Services::AlertHistogramCalculator::HistogramReport)
      expect(report.total_alerts).to eq(4)
      expect(report.hourly_slots.size).to eq(24)
      expect(report.day_slots.size).to eq(7)

      # Slot for 14:00 (base_time) has 1 warning and 1 critical
      slot14 = report.hourly_slots[14]
      expect(slot14.warning_count).to eq(1)
      expect(slot14.critical_count).to eq(1)

      # Slot for 15:00 has 1 recovery
      slot15 = report.hourly_slots[15]
      expect(slot15.ok_count).to eq(1)

      # Peak hour is 14:00 (2 problem alerts)
      expect(report.peak_hour).to eq(14)
      expect(report.peak_hour_label).to eq('14:00')
      expect(report.peak_hour_count).to eq(2)

      # Series data arrays
      expect(report.warning_series.size).to eq(24)
      expect(report.critical_series.size).to eq(24)
      expect(report.recovery_series.size).to eq(24)

      # Top producers
      expect(report.top_producers).to be_an(Array)
      expect(report.top_producers.first[:name]).to eq('srv-db01 / MySQL')
    end

    it 'handles empty alert lists gracefully' do
      report = described_class.analyze([])
      expect(report.total_alerts).to eq(0)
      expect(report.hourly_slots.size).to eq(24)
      expect(report.peak_hour_count).to eq(0)
      expect(report.top_producers).to be_empty
    end
  end
end
