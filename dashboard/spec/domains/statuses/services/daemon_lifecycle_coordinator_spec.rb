# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::DaemonLifecycleCoordinator do
  let(:coordinator) { described_class.new }

  describe 'Lifecycle controls' do
    it 'starts in stopped state and transitions to running' do
      expect(coordinator.status.stopped?).to be true

      coordinator.start!
      status = coordinator.status
      expect(status.running?).to be true
      expect(status.state).to eq(:running)
      expect(status.uptime_seconds).to be >= 0

      coordinator.pause!
      expect(coordinator.status.paused?).to be true

      coordinator.resume!
      expect(coordinator.status.running?).to be true

      coordinator.stop!
      expect(coordinator.status.stopped?).to be true
    end

    it 'executes due checks during tick! and broadcasts events' do
      coordinator.start!
      now = Time.now

      # Schedule a service check in the queue
      coordinator.event_queue.schedule(
        type: :service_check,
        run_time: now - 5,
        target: 'HTTP on localhost'
      )

      executed = coordinator.tick!(now)
      expect(executed.size).to eq(1)
      expect(executed.first.target).to eq('HTTP on localhost')

      # Check radio dispatcher received broadcast
      history = coordinator.radio_dispatcher.channel_history(:service_checks)
      expect(history.first[:payload][:target]).to eq('HTTP on localhost')

      coordinator.stop!
    end
  end
end
