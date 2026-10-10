# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::StateRetention do
  let(:sample_retention_text) do
    <<~RETENTION
      info {
        created=1728550000
        version=4.4.6
        last_update_check=1728550000
      }

      hoststatus {
        host_name=web-server-01
        has_been_checked=1
        current_state=0
        state_type=1
        plugin_output=PING OK - Packet loss = 0%
        performance_data=rta=0.050ms;100.000;500.000;0; pl=0%;20;60;;
        last_check=1728550000
        next_check=1728550060
        is_flapping=0
        percent_state_change=0.0
        problem_has_been_acknowledged=0
        notifications_enabled=1
        active_checks_enabled=1
        scheduled_downtime_depth=0
      }

      servicestatus {
        host_name=web-server-01
        service_description=HTTP Check
        has_been_checked=1
        current_state=2
        state_type=1
        plugin_output=HTTP CRITICAL - Connection refused
        performance_data=time=0.024s;
        last_check=1728550000
        next_check=1728550060
        is_flapping=1
        percent_state_change=34.5
        problem_has_been_acknowledged=1
        notifications_enabled=1
        active_checks_enabled=1
        scheduled_downtime_depth=0
      }
    RETENTION
  end

  describe '.parse' do
    it 'correctly parses info block metadata' do
      snapshot = described_class.parse(sample_retention_text)
      expect(snapshot.info['created']).to eq(1728550000)
      expect(snapshot.info['version']).to eq('4.4.6')
    end

    it 'correctly parses host status attributes and types' do
      snapshot = described_class.parse(sample_retention_text)
      host = snapshot.hosts['web-server-01']

      expect(host).to be_present
      expect(host['current_state']).to eq(0)
      expect(host['plugin_output']).to eq('PING OK - Packet loss = 0%')
      expect(host['is_flapping']).to eq(0)
      expect(host['percent_state_change']).to eq(0.0)
      expect(snapshot.host_count).to eq(1)
    end

    it 'correctly parses service status attributes and types' do
      snapshot = described_class.parse(sample_retention_text)
      svc = snapshot.services.dig('web-server-01', 'HTTP Check')

      expect(svc).to be_present
      expect(svc['current_state']).to eq(2)
      expect(svc['is_flapping']).to eq(1)
      expect(svc['percent_state_change']).to eq(34.5)
      expect(svc['problem_has_been_acknowledged']).to eq(1)
      expect(snapshot.service_count).to eq(1)
    end
  end

  describe '.dump' do
    it 'serializes hosts and services back to valid retention format' do
      hosts = {
        'db-primary' => {
          name: 'db-primary',
          status_code: 0,
          plugin_output: 'UP',
          state_type: 'HARD',
          flapping: false,
          percent_state_change: 0.0
        }
      }
      services = {
        'db-primary' => {
          'Postgres Port' => {
            description: 'Postgres Port',
            status_code: 2,
            plugin_output: 'PORT CLOSED',
            state_type: 'HARD',
            flapping: true,
            percent_state_change: 32.1
          }
        }
      }

      dumped = described_class.dump(hosts: hosts, services: services)

      expect(dumped).to include('hoststatus {')
      expect(dumped).to include('host_name=db-primary')
      expect(dumped).to include('servicestatus {')
      expect(dumped).to include('service_description=Postgres Port')
      expect(dumped).to include('percent_state_change=32.1')

      # Roundtrip verification: parse dumped string
      reparsed = described_class.parse(dumped)
      expect(reparsed.hosts['db-primary']['host_name']).to eq('db-primary')
      expect(reparsed.services.dig('db-primary', 'Postgres Port')['current_state']).to eq(2)
      expect(reparsed.services.dig('db-primary', 'Postgres Port')['is_flapping']).to eq(1)
    end
  end
end
