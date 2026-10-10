# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::TimeperiodEvaluator do
  # 2026-10-10 is Saturday (wday = 6)
  # 2026-10-12 is Monday (wday = 1)
  let(:saturday_noon) { Time.new(2026, 10, 10, 12, 0, 0) }
  let(:monday_10am)   { Time.new(2026, 10, 12, 10, 0, 0) }
  let(:monday_8pm)    { Time.new(2026, 10, 12, 20, 0, 0) }

  let(:workhours_tp) do
    {
      'name' => 'workhours',
      'monday' => '09:00-17:00',
      'tuesday' => '09:00-17:00',
      'wednesday' => '09:00-17:00',
      'thursday' => '09:00-17:00',
      'friday' => '09:00-17:00'
    }
  end

  describe '.active?' do
    it 'always returns true for 24x7 period' do
      expect(described_class.active?('24x7', test_time: saturday_noon)).to be true
      expect(described_class.active?({ 'name' => '24x7' }, test_time: monday_8pm)).to be true
      expect(described_class.active?(nil)).to be true
    end

    it 'returns true during work hours on weekdays' do
      expect(described_class.active?(workhours_tp, test_time: monday_10am)).to be true
    end

    it 'returns false outside work hours on weekdays' do
      expect(described_class.active?(workhours_tp, test_time: monday_8pm)).to be false
    end

    it 'returns false on weekends when not configured' do
      expect(described_class.active?(workhours_tp, test_time: saturday_noon)).to be false
    end

    it 'respects exclusions e.g. holiday calendar overriding normal days' do
      holiday_tp = {
        'name' => 'company_holiday',
        'monday' => '00:00-24:00'
      }

      workhours_with_holiday = workhours_tp.merge('exclude' => ['company_holiday'])
      all_periods = {
        'company_holiday' => holiday_tp,
        'workhours' => workhours_with_holiday
      }

      # Monday 10am would normally be active, but is excluded by holiday!
      expect(described_class.active?(workhours_with_holiday, test_time: monday_10am, all_periods: all_periods)).to be false
    end
  end
end
