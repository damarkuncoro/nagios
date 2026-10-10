require 'rails_helper'

RSpec.describe Statuses::Services::FreshnessDetector do
  let(:now) { Time.now }

  describe '.stale?' do
    it 'returns false when next_check is in the future' do
      record = { next_check: now + 60, checks_enabled: true }
      expect(described_class.stale?(record, current_time: now)).to be false
    end

    it 'returns false when next_check is within tolerance' do
      record = { next_check: now - 120, checks_enabled: true }
      expect(described_class.stale?(record, tolerance_seconds: 300, current_time: now)).to be false
    end

    it 'returns true when next_check is overdue beyond tolerance' do
      record = { next_check: now - 600, checks_enabled: true }
      expect(described_class.stale?(record, tolerance_seconds: 300, current_time: now)).to be true
    end

    it 'returns false if checks_enabled is false (intentionally paused)' do
      record = { next_check: now - 1000, checks_enabled: false }
      expect(described_class.stale?(record, current_time: now)).to be false
    end

    it 'returns false for nil records' do
      expect(described_class.stale?(nil, current_time: now)).to be false
    end
  end

  describe 'Entity integration' do
    it 'HostStatus responds to stale?' do
      host = Statuses::Entities::HostStatus.new(
        name: 'test-host',
        status: 2,
        next_check: now + 120
      )
      expect(host.stale?).to be false
      expect(host.to_h).to have_key(:stale)
    end

    it 'ServiceStatus responds to stale? and state helpers' do
      service = Statuses::Entities::ServiceStatus.new(
        host_name: 'test-host',
        description: 'HTTP',
        status: 2,
        state_type: 'HARD',
        next_check: now + 120
      )
      expect(service.stale?).to be false
      expect(service.hard_state?).to be true
      expect(service.soft_state?).to be false
      expect(service.to_h).to have_key(:stale)
    end
  end
end
