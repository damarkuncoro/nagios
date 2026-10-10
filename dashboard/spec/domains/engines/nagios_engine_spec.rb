require 'rails_helper'

RSpec.describe Engines::NagiosEngine do
  describe '.program_status' do
    it 'fetches and parses program status JSON' do
      mock_json = {
        data: {
          programstatus: {
            version: '4.5.12',
            nagios_pid: 22,
            enable_notifications: true,
            execute_service_checks: true,
            program_start: 1_791_512_866_000
          }
        }
      }.to_json

      allow(Net::HTTP).to receive(:start).and_return(double(is_a?: true, body: mock_json))

      status = described_class.program_status
      expect(status[:version]).to eq('4.5.12')
      expect(status[:pid]).to eq(22)
      expect(status[:notifications_enabled]).to be true
    end
  end

  describe '.hosts' do
    it 'fetches and returns HostStatus domain entities' do
      mock_json = {
        data: {
          hostlist: {
            localhost: {
              status: 2,
              plugin_output: 'PING OK',
              last_check: 1_791_512_845_000
            }
          }
        }
      }.to_json

      allow(Net::HTTP).to receive(:start).and_return(double(is_a?: true, body: mock_json))

      hosts = described_class.hosts
      expect(hosts.size).to eq(1)
      expect(hosts.first).to be_a(Statuses::Entities::HostStatus)
      expect(hosts.first.name).to eq('localhost')
      expect(hosts.first.status).to eq('UP')
    end
  end

  describe '.services' do
    it 'fetches and returns ServiceStatus domain entities' do
      mock_json = {
        data: {
          servicelist: {
            localhost: {
              "Current Load": {
                status: 2,
                plugin_output: 'OK - load average: 0.1, 0.2, 0.3'
              }
            }
          }
        }
      }.to_json

      allow(Net::HTTP).to receive(:start).and_return(double(is_a?: true, body: mock_json))

      services = described_class.services
      expect(services.size).to eq(1)
      expect(services.first).to be_a(Statuses::Entities::ServiceStatus)
      expect(services.first.description).to eq('Current Load')
      expect(services.first.status).to eq('OK')
    end
  end

  describe '.host_objects' do
    it 'fetches and returns host definition objects hash' do
      mock_json = { data: { hostlist: { "localhost" => { "check_command" => "check-host-alive" } } } }.to_json
      allow(Net::HTTP).to receive(:start).and_return(double(is_a?: true, body: mock_json))

      hosts = described_class.host_objects
      expect(hosts).to be_a(Hash)
      expect(hosts["localhost"]["check_command"]).to eq("check-host-alive")
    end
  end

  describe '.service_objects' do
    it 'fetches and returns service definition objects hash' do
      mock_json = { data: { servicelist: { "localhost" => { "HTTP" => { "check_command" => "check_http" } } } } }.to_json
      allow(Net::HTTP).to receive(:start).and_return(double(is_a?: true, body: mock_json))

      services = described_class.service_objects
      expect(services).to be_a(Hash)
      expect(services.dig("localhost", "HTTP", "check_command")).to eq("check_http")
    end
  end
end
