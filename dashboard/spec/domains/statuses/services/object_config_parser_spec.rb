# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::ObjectConfigParser do
  let(:sample_config) do
    <<~CFG
      # Abstract Template
      define host {
          name                    linux-server
          register                0
          check_period            24x7
          max_check_attempts      3
          notification_interval   120
      }

      # Active Host Inheriting from Template
      define host {
          use                     linux-server
          host_name               web-prod-01
          alias                   Production Web 01
          address                 192.168.1.50
          check_command           check_ping
      }

      define service {
          host_name               web-prod-01
          service_description     HTTP
          check_command           check_http
          check_interval          5
      }

      define command {
          command_name            check_ping
          command_line            $USER1$/check_ping -H $HOSTADDRESS$ -w 100.0,20% -c 500.0,60%
      }

      define contact {
          contact_name            admin
          alias                   SysAdmin
          email                   admin@domain.local
      }

      define hostgroup {
          hostgroup_name          web-servers
          alias                   Web Cluster
          members                 web-prod-01
      }
    CFG
  end

  describe '#parse' do
    it 'parses objects and resolves template inheritance' do
      catalog = described_class.parse(sample_config)

      expect(catalog).to be_a(Statuses::Services::ObjectConfigParser::ConfigCatalog)
      expect(catalog.hosts.size).to eq(1)
      expect(catalog.services.size).to eq(1)
      expect(catalog.commands.size).to eq(1)
      expect(catalog.contacts.size).to eq(1)
      expect(catalog.hostgroups.size).to eq(1)

      # Host should inherit check_period and max_check_attempts from linux-server template
      host = catalog.hosts['web-prod-01']
      expect(host['address']).to eq('192.168.1.50')
      expect(host['check_period']).to eq('24x7')
      expect(host['max_check_attempts']).to eq('3')
      expect(host['notification_interval']).to eq('120')

      # Template register 0 should not be in active hosts
      expect(catalog.hosts).not_to have_key('linux-server')
    end

    it 'returns empty catalog for empty string' do
      catalog = described_class.parse('')
      expect(catalog.total_objects).to eq(0)
    end
  end

  describe '#serialize' do
    it 'serializes catalog back into valid Nagios .cfg format' do
      catalog = described_class.parse(sample_config)
      serialized = described_class.serialize(catalog)

      expect(serialized).to include('define host {')
      expect(serialized).to include('define service {')
      expect(serialized).to include('define command {')
      expect(serialized).to include('define contact {')
      expect(serialized).to include('define hostgroup {')

      # Roundtrip parsing
      reparsed = described_class.parse(serialized)
      expect(reparsed.hosts.size).to eq(catalog.hosts.size)
      expect(reparsed.services.size).to eq(catalog.services.size)
      expect(reparsed.commands.size).to eq(catalog.commands.size)
    end
  end
end
