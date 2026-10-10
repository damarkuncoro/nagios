# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::NotificationViability do
  let(:now) { Time.new(2026, 10, 10, 12, 0, 0) }

  describe '.check' do
    it 'returns viable when forced option is set regardless of other blocks' do
      target = { notifications_enabled: false, scheduled_downtime_depth: 2 }
      res = described_class.check(
        target,
        type: :normal,
        options: { forced: true },
        global_notifications_enabled: false
      )
      expect(res.viable?).to be true
      expect(res.code).to eq(:forced_override)
    end

    it 'blocks notification when global notifications are disabled' do
      target = { notifications_enabled: true }
      res = described_class.check(target, global_notifications_enabled: false)
      expect(res.viable?).to be false
      expect(res.code).to eq(:global_notifications_disabled)
    end

    it 'blocks notification when target object notifications are disabled' do
      target = { notifications_enabled: false }
      res = described_class.check(target, global_notifications_enabled: true)
      expect(res.viable?).to be false
      expect(res.code).to eq(:object_notifications_disabled)
    end

    it 'blocks notification when all parent nodes are in failure states' do
      target = { notifications_enabled: true }
      res = described_class.check(
        target,
        parent_states: %w[DOWN CRITICAL UNREACHABLE]
      )
      expect(res.viable?).to be false
      expect(res.code).to eq(:parent_failure_suppression)
    end

    it 'allows notification if at least one parent node is OK' do
      target = { notifications_enabled: true }
      res = described_class.check(
        target,
        parent_states: %w[DOWN OK]
      )
      expect(res.viable?).to be true
    end

    it 'suppresses normal alerts during scheduled downtime' do
      target = { notifications_enabled: true, scheduled_downtime_depth: 1 }
      res = described_class.check(target, type: :normal)
      expect(res.viable?).to be false
      expect(res.code).to eq(:in_scheduled_downtime)
    end

    it 'suppresses alerts when parent host is in scheduled downtime' do
      target = { notifications_enabled: true, scheduled_downtime_depth: 0 }
      host = { scheduled_downtime_depth: 1 }
      res = described_class.check(target, host: host, type: :normal)
      expect(res.viable?).to be false
      expect(res.code).to eq(:in_scheduled_downtime)
    end

    it 'rejects acknowledgement notification if state is OK' do
      target = { notifications_enabled: true, status: 0 }
      res = described_class.check(target, type: :acknowledgement)
      expect(res.viable?).to be false
      expect(res.code).to eq(:no_problem_for_ack)
    end

    it 'permits acknowledgement notification if state is CRITICAL or WARNING' do
      target = { notifications_enabled: true, status: 2 }
      res = described_class.check(target, type: :acknowledgement)
      expect(res.viable?).to be true
    end

    it 'throttles notifications when within notification_interval window' do
      target = {
        notifications_enabled: true,
        current_notification_number: 1,
        notification_interval: 30, # 30 minutes
        last_notification: now - 10.minutes
      }
      res = described_class.check(target, type: :normal, current_time: now)
      expect(res.viable?).to be false
      expect(res.code).to eq(:throttled_by_interval)
    end

    it 'permits notification when past the notification_interval window' do
      target = {
        notifications_enabled: true,
        current_notification_number: 1,
        notification_interval: 30, # 30 minutes
        last_notification: now - 45.minutes
      }
      res = described_class.check(target, type: :normal, current_time: now)
      expect(res.viable?).to be true
    end
  end
end
