require 'rails_helper'

RSpec.describe Statuses::UseCases::ScheduleDowntime do
  describe '.service' do
    it 'delegates to NagiosEngine.schedule_service_downtime' do
      expect(Engines::NagiosEngine).to receive(:schedule_service_downtime).with(
        'localhost', 'HTTP', duration_hours: 2, author: 'admin', comment: 'Update'
      ).and_return(true)

      result = described_class.service('localhost', 'HTTP', duration_hours: 2, author: 'admin', comment: 'Update')
      expect(result).to be true
    end
  end
end
