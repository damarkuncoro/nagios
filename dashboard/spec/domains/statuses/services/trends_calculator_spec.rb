# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::TrendsCalculator do
  let(:calculator) { described_class.new }

  describe '#calculate_time_in_state' do
    let(:start_time) { Time.at(1_000_000) }
    let(:end_time) { Time.at(1_003_600) } # 3600 seconds (1 hour)

    context 'with continuous OK state' do
      it 'reports 100% OK and 100% availability' do
        result = calculator.calculate_time_in_state(
          transitions: [],
          start_time: start_time,
          end_time: end_time,
          initial_state: 'OK'
        )

        expect(result.monitored_seconds).to eq(3600)
        expect(result.time_ok).to eq(3600)
        expect(result.percent_ok).to eq(100.0)
        expect(result.availability_pct).to eq(100.0)
        expect(result.total_transitions).to eq(0)
      end
    end

    context 'with outage period and recovery' do
      let(:transitions) do
        [
          { timestamp: 1_000_600, state: 'CRITICAL' }, # starts at 600s
          { timestamp: 1_001_800, state: 'OK' }        # recovers at 1800s (outage = 1200s)
        ]
      end

      it 'accurately splits durations and computes MTTR' do
        result = calculator.calculate_time_in_state(
          transitions: transitions,
          start_time: start_time,
          end_time: end_time,
          initial_state: 'OK'
        )

        # 0..600: OK (600s), 600..1800: CRITICAL (1200s), 1800..3600: OK (1800s)
        # Total OK: 2400s (66.67%), Critical: 1200s (33.33%)
        expect(result.monitored_seconds).to eq(3600)
        expect(result.time_ok).to eq(2400)
        expect(result.time_critical).to eq(1200)
        expect(result.percent_ok).to eq(66.67)
        expect(result.percent_critical).to eq(33.33)
        expect(result.availability_pct).to eq(66.67)
        expect(result.mean_time_to_recovery).to eq(1200.0)
        expect(result.total_transitions).to eq(2)
      end
    end

    context 'with scheduled downtime exclusion' do
      let(:transitions) do
        [
          { timestamp: 1_001_000, state: 'CRITICAL', in_downtime: true },
          { timestamp: 1_002_000, state: 'OK', in_downtime: false }
        ]
      end

      it 'attributes downtime seconds and adjusts availability percentage' do
        result = calculator.calculate_time_in_state(
          transitions: transitions,
          start_time: start_time,
          end_time: end_time,
          initial_state: 'OK'
        )

        # Downtime: 1000s (1001000..1002000)
        # OK: 2600s (1000s before + 1600s after)
        # Effective non-downtime: 2600s -> Availability: 2600 / 2600 = 100%
        expect(result.time_downtime).to eq(1000)
        expect(result.time_ok).to eq(2600)
        expect(result.availability_pct).to eq(100.0)
      end
    end
  end

  describe '#aggregate_daily' do
    let(:fixed_now) { Time.new(2026, 10, 10, 12, 0, 0) }
    let(:alerts) do
      [
        { timestamp: Time.new(2026, 10, 10, 10, 0, 0), state: 'OK' },
        { timestamp: Time.new(2026, 10, 10, 11, 0, 0), state: 'WARNING' },
        { timestamp: Time.new(2026, 10, 9, 8, 0, 0), state: 'CRITICAL' }
      ]
    end

    it 'groups alerts into ordered daily buckets' do
      buckets = calculator.aggregate_daily(alerts: alerts, days: 3, now: fixed_now)

      expect(buckets.size).to eq(3)

      today_bucket = buckets.last
      expect(today_bucket.date_str).to eq('10 Oct')
      expect(today_bucket.ok_count).to eq(1)
      expect(today_bucket.warning_count).to eq(1)
      expect(today_bucket.total_alerts).to eq(2)

      yesterday_bucket = buckets[-2]
      expect(yesterday_bucket.date_str).to eq('09 Oct')
      expect(yesterday_bucket.critical_count).to eq(1)
    end
  end
end
