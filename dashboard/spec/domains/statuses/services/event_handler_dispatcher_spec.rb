# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::EventHandlerDispatcher do
  let(:broker) { Statuses::Events::Broker }

  before do
    broker.clear_history!
  end

  describe '.handle_service_event' do
    let(:host) { { 'name' => 'prod-api', 'address' => '10.0.0.5' } }
    let(:service) do
      {
        'description' => 'Sidekiq Workers',
        'event_handler' => '$USER1$/eventhandlers/restart_service.sh $HOSTNAME$ $SERVICEDESC$ $SERVICESTATE$ $SERVICESTATETYPE$ $SERVICEATTEMPT$',
        'event_handler_enabled' => true
      }
    end

    it 'dispatches service event handler and publishes broker event' do
      executed_command = nil
      runner = ->(cmd) { executed_command = cmd }

      res = described_class.handle_service_event(
        service: service,
        host: host,
        old_state: 'OK',
        new_state: 'CRITICAL',
        state_type: 'HARD',
        attempt: 3,
        max_attempts: 3,
        runner: runner,
        event_broker: broker
      )

      expect(res.dispatched?).to be true
      expect(executed_command).to include('restart_service.sh prod-api "Sidekiq Workers" CRITICAL HARD 3/3')

      events = broker.history
      expect(events.first[:type]).to eq(:state_change)
      expect(events.first[:payload][:service]).to eq('Sidekiq Workers')
      expect(events.first[:payload][:new_state]).to eq('CRITICAL')
    end

    it 'aborts dispatch when global event handlers are disabled' do
      res = described_class.handle_service_event(
        service: service,
        host: host,
        old_state: 'OK',
        new_state: 'CRITICAL',
        global_handlers_enabled: false
      )

      expect(res.dispatched?).to be false
      expect(res.reason).to eq('Global event handlers are disabled')
    end

    it 'aborts dispatch when service has event handlers disabled' do
      svc_disabled = service.merge('event_handler_enabled' => false)
      res = described_class.handle_service_event(
        service: svc_disabled,
        host: host,
        old_state: 'OK',
        new_state: 'CRITICAL'
      )

      expect(res.dispatched?).to be false
      expect(res.reason).to eq('Event handler is disabled for this service')
    end
  end

  describe '.handle_host_event' do
    let(:host) do
      {
        'name' => 'db-cluster-01',
        'address' => '10.0.0.10',
        'event_handler' => '$USER1$/eventhandlers/failover_host.sh $HOSTNAME$ $HOSTSTATE$ $HOSTSTATETYPE$ $HOSTATTEMPT$',
        'event_handler_enabled' => true
      }
    end

    it 'dispatches host event handler and publishes broker event' do
      executed_command = nil
      runner = ->(cmd) { executed_command = cmd }

      res = described_class.handle_host_event(
        host: host,
        old_state: 'UP',
        new_state: 'DOWN',
        state_type: 'HARD',
        attempt: 2,
        max_attempts: 2,
        runner: runner,
        event_broker: broker
      )

      expect(res.dispatched?).to be true
      expect(executed_command).to include('failover_host.sh db-cluster-01 DOWN HARD 2/2')

      events = broker.history
      expect(events.first[:type]).to eq(:state_change)
      expect(events.first[:payload][:type]).to eq('host')
      expect(events.first[:payload][:host]).to eq('db-cluster-01')
      expect(events.first[:payload][:new_state]).to eq('DOWN')
    end
  end
end
