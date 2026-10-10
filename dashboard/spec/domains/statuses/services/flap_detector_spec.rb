# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::FlapDetector do
  describe '.calculate_percent_change' do
    it 'returns 0.0 for empty or single state array' do
      expect(described_class.calculate_percent_change([])).to eq(0.0)
      expect(described_class.calculate_percent_change([0])).to eq(0.0)
    end

    it 'returns 0.0 for completely stable history' do
      history = [0] * 21
      expect(described_class.calculate_percent_change(history)).to eq(0.0)
    end

    it 'calculates curved percent change for alternating flapping states' do
      # Alternating 0 and 2 every cycle
      history = [0, 2] * 10 + [0] # 21 entries
      percent = described_class.calculate_percent_change(history)
      expect(percent).to be > 50.0
    end

    it 'weights recent state changes more heavily than older changes' do
      # History with changes only in the recent past (at end of window)
      recent_changes = [0] * 15 + [2, 0, 2, 0, 2, 0]
      # History with changes only in distant past (at start of window)
      distant_changes = [2, 0, 2, 0, 2, 0] + [0] * 15

      recent_percent = described_class.calculate_percent_change(recent_changes)
      distant_percent = described_class.calculate_percent_change(distant_changes)

      expect(recent_percent).to be > distant_percent
    end
  end

  describe '.evaluate' do
    it 'marks flapping as true when percent change reaches high threshold' do
      # Highly volatile history
      history = [0, 2] * 10 + [0]
      result = described_class.evaluate(history, current_flapping: false, low_threshold: 20.0, high_threshold: 30.0)

      expect(result.flapping?).to be true
      expect(result.started?).to be true
      expect(result.decision).to eq(:flapping)
    end

    it 'clears flapping when percent change drops below low threshold' do
      # Stable history
      history = [0] * 21
      result = described_class.evaluate(history, current_flapping: true, low_threshold: 20.0, high_threshold: 30.0)

      expect(result.flapping?).to be false
      expect(result.stopped?).to be true
      expect(result.decision).to eq(:stable)
    end

    it 'maintains existing flap status when within hysteresis undecided zone' do
      # Construct moderate changes in middle
      history = [0] * 14 + [2, 0, 2, 0, 0, 0, 0]
      percent = described_class.calculate_percent_change(history)
      # Force low/high bounds so percent falls in between
      result_while_flapping = described_class.evaluate(
        history,
        current_flapping: true,
        low_threshold: percent - 5.0,
        high_threshold: percent + 5.0
      )
      expect(result_while_flapping.flapping?).to be true
      expect(result_while_flapping.decision).to eq(:undecided)

      result_while_stable = described_class.evaluate(
        history,
        current_flapping: false,
        low_threshold: percent - 5.0,
        high_threshold: percent + 5.0
      )
      expect(result_while_stable.flapping?).to be false
      expect(result_while_stable.decision).to eq(:undecided)
    end

    it 'clears flap status if flap detection is disabled' do
      history = [0, 2] * 10 + [0]
      result = described_class.evaluate(history, current_flapping: true, flap_detection_enabled: false)

      expect(result.flapping?).to be false
      expect(result.stopped?).to be true
      expect(result.decision).to eq(:disabled)
    end
  end

  describe '.check_and_notify' do
    let(:broker) { Statuses::Events::Broker }

    before do
      broker.clear_history!
    end

    it 'publishes FLAPPING event when object starts flapping' do
      target = { name: 'web-srv', flapping: false }
      history = [0, 2] * 10 + [0]

      result = described_class.check_and_notify(target, state_history: history, event_broker: broker)

      expect(result.started?).to be true
      events = broker.history
      expect(events.first[:type]).to eq(:flapping)
      expect(events.first[:payload][:action]).to eq('started')
      expect(events.first[:payload][:target]).to eq('web-srv')
    end

    it 'publishes FLAPPING event when object stops flapping' do
      target = { name: 'db-srv', flapping: true }
      history = [0] * 21

      result = described_class.check_and_notify(target, state_history: history, event_broker: broker)

      expect(result.stopped?).to be true
      events = broker.history
      expect(events.first[:type]).to eq(:flapping)
      expect(events.first[:payload][:action]).to eq('stopped')
      expect(events.first[:payload][:target]).to eq('db-srv')
    end
  end
end
