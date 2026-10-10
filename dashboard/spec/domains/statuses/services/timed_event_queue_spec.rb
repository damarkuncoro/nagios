# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::TimedEventQueue do
  let(:queue) { described_class.new }
  let(:base_time) { Time.new(2026, 10, 10, 12, 0, 0) }

  describe '#schedule' do
    it 'inserts events sorted by ascending run_time' do
      e3 = queue.schedule(type: :service_check, run_time: base_time + 30)
      e1 = queue.schedule(type: :service_check, run_time: base_time + 10)
      e2 = queue.schedule(type: :service_check, run_time: base_time + 20)

      due = queue.peek_due(base_time + 25)
      expect(due.map(&:id)).to eq([e1.id, e2.id])
      expect(queue.size).to eq(3)
    end
  end

  describe '#schedule_interleaved' do
    it 'spreads check times evenly to avoid check spikes' do
      hosts = %w[h1 h2 h3 h4]
      events = queue.schedule_interleaved(
        hosts,
        type: :host_check,
        interval_seconds: 60,
        start_time: base_time
      )

      expect(events.size).to eq(4)
      # Step = 60 / 4 = 15 seconds
      expect(events[0].run_time).to eq(base_time.to_i)
      expect(events[1].run_time).to eq(base_time.to_i + 15)
      expect(events[2].run_time).to eq(base_time.to_i + 30)
      expect(events[3].run_time).to eq(base_time.to_i + 45)
    end
  end

  describe '#process_due' do
    it 'executes due events and reschedules recurring events' do
      executed_ids = []

      # Recurring event every 60s
      e_rec = queue.schedule(
        type: :service_check,
        run_time: base_time - 10,
        interval: 60
      ) { |e| executed_ids << e.id }

      # One-off event
      e_once = queue.schedule(
        type: :notification,
        run_time: base_time - 5,
        interval: 0
      ) { |e| executed_ids << e.id }

      # Future event
      e_future = queue.schedule(
        type: :service_check,
        run_time: base_time + 100
      )

      processed = queue.process_due(base_time)

      expect(processed.map(&:id)).to match_array([e_rec.id, e_once.id])
      expect(executed_ids).to match_array([e_rec.id, e_once.id])

      # Queue should still contain future event + rescheduled recurring event
      expect(queue.size).to eq(2)
      stats = queue.stats
      expect(stats[:total_queued]).to eq(2)
      expect(stats[:event_counts][:service_check]).to eq(2)
    end
  end

  describe '#cancel' do
    it 'removes specific event from queue' do
      e = queue.schedule(type: :custom, run_time: base_time)
      expect(queue.size).to eq(1)

      queue.cancel(e.id)
      expect(queue.size).to eq(0)
    end
  end
end
