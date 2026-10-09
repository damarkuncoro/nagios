require 'rails_helper'

RSpec.describe Statuses::Services::NotificationService do
  describe '.send_alert' do
    it 'returns false when WEBHOOK_URL is not set' do
      stub_const('Statuses::Services::NotificationService::WEBHOOK_URL', nil)
      expect(described_class.send_alert(host_name: 'h1', service_desc: 'HTTP', status: 'CRITICAL', plugin_output: 'Down')).to be false
    end

    it 'posts JSON payload to webhook when WEBHOOK_URL is set' do
      stub_const('Statuses::Services::NotificationService::WEBHOOK_URL', 'https://hooks.slack.com/services/test')
      allow(Net::HTTP).to receive(:start).and_return(double(is_a?: true))

      result = described_class.send_alert(host_name: 'h1', service_desc: 'HTTP', status: 'CRITICAL', plugin_output: 'Down')
      expect(result).to be true
    end
  end
end
