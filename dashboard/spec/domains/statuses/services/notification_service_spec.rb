# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::NotificationService do
  describe '.detect_platform' do
    it 'detects Slack from webhook URL' do
      expect(described_class.detect_platform('https://hooks.slack.com/services/T00/B00/X00')).to eq(:slack)
    end

    it 'detects Discord from webhook URL' do
      expect(described_class.detect_platform('https://discord.com/api/webhooks/123/abc')).to eq(:discord)
      expect(described_class.detect_platform('https://discordapp.com/api/webhooks/123/abc')).to eq(:discord)
    end

    it 'defaults to generic for other URLs' do
      expect(described_class.detect_platform('https://api.mycompany.com/alerts/webhook')).to eq(:generic)
    end
  end

  describe '.build_payload' do
    it 'builds Slack payload with attachments' do
      payload = described_class.build_payload(:slack, 'app01', 'HTTP', 'CRITICAL', '500 Error')
      expect(payload[:attachments]).to be_an(Array)
      expect(payload[:attachments].first[:color]).to eq('#EF4444')
      expect(payload[:attachments].first[:title]).to include('HTTP on app01 is CRITICAL')
    end

    it 'builds Discord payload with embeds' do
      payload = described_class.build_payload(:discord, 'app01', 'HTTP', 'CRITICAL', '500 Error')
      expect(payload[:embeds]).to be_an(Array)
      expect(payload[:embeds].first[:color]).to eq(0xEF4444)
      expect(payload[:embeds].first[:title]).to include('HTTP on app01 is CRITICAL')
    end

    it 'builds generic JSON payload' do
      payload = described_class.build_payload(:generic, 'app01', 'HTTP', 'CRITICAL', '500 Error')
      expect(payload[:event]).to eq('nagios_alert')
      expect(payload[:host_name]).to eq('app01')
      expect(payload[:service_desc]).to eq('HTTP')
      expect(payload[:status]).to eq('CRITICAL')
    end
  end

  describe '.send_alert' do
    it 'returns false when target_url and WEBHOOK_URL are not set' do
      stub_const('Statuses::Services::NotificationService::WEBHOOK_URL', nil)
      expect(described_class.send_alert(host_name: 'h1', service_desc: 'HTTP', status: 'CRITICAL', plugin_output: 'Down')).to be false
    end

    it 'posts Slack JSON payload when target_url is a Slack webhook' do
      slack_url = 'https://hooks.slack.com/services/test'
      response_mock = double(is_a?: true, code: '200', body: 'ok')
      allow(Net::HTTP).to receive(:start).and_return(response_mock)

      result = described_class.send_alert(
        host_name: 'h1',
        service_desc: 'HTTP',
        status: 'CRITICAL',
        plugin_output: 'Down',
        target_url: slack_url
      )
      expect(result).to be true
    end

    it 'posts Discord JSON payload when target_url is a Discord webhook' do
      discord_url = 'https://discord.com/api/webhooks/123/xyz'
      response_mock = double(is_a?: false, code: '204', body: '') # Discord 204 No Content
      allow(Net::HTTP).to receive(:start).and_return(response_mock)

      delivery = described_class.deliver_alert(
        host_name: 'h1',
        service_desc: 'HTTP',
        status: 'WARNING',
        plugin_output: 'High Latency',
        target_url: discord_url
      )
      expect(delivery.success?).to be true
      expect(delivery.platform).to eq(:discord)
      expect(delivery.status_code).to eq(204)
    end

    it 'handles HTTP failure cleanly' do
      webhook_url = 'https://api.example.com/webhook'
      response_mock = double(is_a?: false, code: '500', body: 'Internal Server Error')
      allow(Net::HTTP).to receive(:start).and_return(response_mock)

      delivery = described_class.deliver_alert(
        host_name: 'h1',
        service_desc: 'HTTP',
        status: 'CRITICAL',
        plugin_output: 'Down',
        target_url: webhook_url
      )
      expect(delivery.success?).to be false
      expect(delivery.status_code).to eq(500)
      expect(delivery.error).to include('HTTP 500')
    end

    it 'suppresses notification when viability check fails' do
      mock_service = { 'host_name' => 'h1', 'description' => 'HTTP', 'scheduled_downtime_depth' => 1 }
      viability_mock = Statuses::Services::NotificationViability::ViabilityResult.new(
        viable: false,
        reason: 'Service is currently in scheduled downtime',
        code: :in_scheduled_downtime
      )
      allow(Statuses::Services::NotificationViability).to receive(:check).and_return(viability_mock)

      delivery = described_class.deliver_alert(
        host_name: 'h1',
        service_desc: 'HTTP',
        status: 'CRITICAL',
        plugin_output: 'Down',
        target_url: 'https://hooks.slack.com/services/test',
        service_obj: mock_service,
        check_viability: true
      )
      expect(delivery.success?).to be false
      expect(delivery.error).to include('scheduled downtime')
    end
  end
end
