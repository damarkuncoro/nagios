# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::DowntimeCoordinator do
  let(:coordinator) { described_class.new }
  let(:now) { 1700000000 }

  before do
    coordinator.clear!
  end

  describe '#schedule_host_downtime' do
    it 'schedules fixed host downtime and activates if within window' do
      dt = coordinator.schedule_host_downtime(
        host_name: 'srv-db01',
        start_time: now - 100,
        end_time: now + 3500,
        fixed: true,
        author: 'admin',
        comment: 'Storage maintenance'
      )

      expect(dt).to be_a(Statuses::Services::DowntimeCoordinator::ScheduledDowntime)
      expect(dt.id).to be >= 1000
      expect(dt.host_name).to eq('srv-db01')
      expect(dt.fixed?).to be true
      expect(coordinator.in_downtime?('srv-db01')).to be true
      expect(coordinator.downtime_depth('srv-db01')).to eq(1)
    end

    it 'schedules future fixed downtime without activating immediately' do
      dt = coordinator.schedule_host_downtime(
        host_name: 'srv-web01',
        start_time: now + 1000,
        end_time: now + 4600,
        fixed: true
      )

      expect(dt.active?).to be false
      expect(coordinator.in_downtime?('srv-web01')).to be false
    end
  end

  describe '#schedule_service_downtime' do
    it 'schedules service downtime and tracks depth per service' do
      dt = coordinator.schedule_service_downtime(
        host_name: 'srv-db01',
        service_desc: 'MySQL Query Latency',
        start_time: now - 50,
        end_time: now + 1800,
        fixed: true
      )

      expect(dt.service_downtime?).to be true
      expect(coordinator.in_downtime?('srv-db01', 'MySQL Query Latency')).to be true
      expect(coordinator.in_downtime?('srv-db01', 'Other Svc')).to be false
    end
  end

  describe '#check_pending_flexible_downtime' do
    it 'activates pending flexible downtime when target enters problem state' do
      dt = coordinator.schedule_host_downtime(
        host_name: 'srv-db01',
        start_time: now - 300,
        end_time: now + 3600,
        fixed: false,
        duration: 1800
      )

      expect(dt.active?).to be false
      expect(coordinator.in_downtime?('srv-db01')).to be false

      # Problem detected
      activated = coordinator.check_pending_flexible_downtime('srv-db01', current_state: 'DOWN', current_time: now)
      expect(activated.size).to eq(1)
      expect(dt.active?).to be true
      expect(dt.actual_start_time).to eq(now)
      expect(dt.actual_end_time).to eq(now + 1800)
      expect(coordinator.in_downtime?('srv-db01')).to be true
    end

    it 'does not activate flexible downtime if target state is OK or UP' do
      coordinator.schedule_host_downtime(
        host_name: 'srv-db01',
        start_time: now - 300,
        end_time: now + 3600,
        fixed: false
      )

      activated = coordinator.check_pending_flexible_downtime('srv-db01', current_state: 'UP', current_time: now)
      expect(activated).to be_empty
      expect(coordinator.in_downtime?('srv-db01')).to be false
    end
  end

  describe '#check_for_expired_downtimes' do
    it 'expires active downtime when current time exceeds end time' do
      coordinator.schedule_host_downtime(
        host_name: 'srv-app01',
        start_time: now - 2000,
        end_time: now - 100,
        fixed: true
      )

      expect(coordinator.in_downtime?('srv-app01')).to be true

      expired = coordinator.check_for_expired_downtimes(now)
      expect(expired.size).to eq(1)
      expect(coordinator.in_downtime?('srv-app01')).to be false
    end
  end

  describe '#cancel_downtime' do
    it 'cancels existing downtime and resets depth' do
      dt = coordinator.schedule_host_downtime(
        host_name: 'srv-app01',
        start_time: now - 50,
        end_time: now + 1000,
        fixed: true
      )

      expect(coordinator.in_downtime?('srv-app01')).to be true
      success = coordinator.cancel_downtime(dt.id)

      expect(success).to be true
      expect(coordinator.in_downtime?('srv-app01')).to be false
    end
  end

  describe 'cascading triggered downtimes' do
    it 'activates child downtime when parent downtime starts' do
      parent = coordinator.schedule_host_downtime(
        host_name: 'srv-core01',
        start_time: now - 50,
        end_time: now + 3600,
        fixed: true
      )

      child = coordinator.schedule_service_downtime(
        host_name: 'srv-core01',
        service_desc: 'Core API',
        start_time: now - 50,
        end_time: now + 3600,
        fixed: false,
        triggered_by: parent.id,
        duration: 1800
      )

      expect(child.active?).to be true
      expect(coordinator.in_downtime?('srv-core01', 'Core API')).to be true
    end
  end
end
