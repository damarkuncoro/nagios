# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'NagiosPureRubyEngine' do
  let(:sample_cfg) do
    File.read(Rails.root.join('config/nagios_sample.cfg'))
  end

  describe 'Configuration Parsing' do
    it 'successfully parses sample configuration with hosts and services' do
      catalog = Statuses::Services::ObjectConfigParser.parse(sample_cfg)

      expect(catalog.hosts.keys).to include('localhost', 'gateway')
      expect(catalog.services.size).to eq(4)
      expect(catalog.hosts['gateway']['parents']).to eq('localhost')
    end
  end

  describe 'Daemon Orchestration & State Tracking' do
    let(:event_queue) { Statuses::Services::TimedEventQueue.new }
    let(:worker_pool) { Statuses::Services::WorkerProcessPool.new(max_workers: 4) }
    let(:coordinator) do
      Statuses::Services::DaemonLifecycleCoordinator.new(
        event_queue: event_queue,
        worker_pool: worker_pool
      )
    end

    it 'transitions daemon lifecycle states cleanly' do
      expect(coordinator.status.state).to eq(:stopped)
      coordinator.start!
      expect(coordinator.status.state).to eq(:running)
      coordinator.pause!
      expect(coordinator.status.state).to eq(:paused)
      coordinator.resume!
      expect(coordinator.status.state).to eq(:running)
      coordinator.stop!
      expect(coordinator.status.state).to eq(:stopped)
    end

    it 'evaluates flapping hysteresis correctly' do
      # 21 alternating state entries to trigger flapping
      oscillating_history = [0, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0]
      result = Statuses::Services::FlapDetector.evaluate(oscillating_history)

      expect(result.flapping?).to be true
      expect(result.percent_state_change).to be > 30.0
    end

    it 'evaluates parent-child host reachability' do
      detector = Statuses::Services::HostReachabilityDetector
      # When parent is DOWN (1), child target is marked UNREACHABLE (2)
      topology = {
        'localhost' => { 'state' => 1 },
        'gateway' => { 'state' => 1, 'parents' => ['localhost'] }
      }
      
      reachability = detector.evaluate('gateway', topology: topology)
      expect(reachability.status).to eq(:unreachable)
    end
  end
end
