# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::ArchiveJsonSerializer do
  let(:serializer) { described_class.new }

  let(:context) do
    {
      log_entries: [
        {
          timestamp: 1672531200,
          category: :alert,
          event_type: 'HOST ALERT',
          host_name: 'web01',
          service_desc: nil,
          state: 'DOWN',
          state_type: 'HARD',
          attempt: 3,
          message: 'PING CRITICAL - Packet loss 100%'
        },
        {
          timestamp: 1672531260,
          category: :alert,
          event_type: 'SERVICE ALERT',
          host_name: 'web01',
          service_desc: 'HTTP',
          state: 'CRITICAL',
          state_type: 'HARD',
          attempt: 3,
          message: 'HTTP CRITICAL - Connection refused'
        },
        {
          timestamp: 1672531300,
          category: :notification,
          event_type: 'HOST NOTIFICATION',
          host_name: 'web01',
          service_desc: nil,
          state: 'DOWN',
          contact_name: 'alice',
          message: 'Host DOWN notification sent via email'
        }
      ],
      hosts: [{ name: 'web01' }],
      services: [{ host_name: 'web01', description: 'HTTP' }],
      program_status: {
        program_start: Time.at(1672500000),
        last_update: Time.at(1672531500)
      },
      user: 'nagiosadmin'
    }
  end

  describe '#serialize_query' do
    it 'handles help query' do
      res = serializer.serialize_query('help', {}, context)
      expect(res[:format_version]).to eq(0)
      expect(res[:result][:cgi]).to eq('archivejson.cgi')
      expect(res[:result][:type_code]).to eq(0)
      expect(res[:data][:valid_queries]).to include('alertlist', 'notificationlist', 'availability')
    end

    it 'handles alertcount query' do
      res = serializer.serialize_query('alertcount', {}, context)
      expect(res[:data][:count][:total]).to eq(2)
    end

    it 'handles alertlist query with filters' do
      res = serializer.serialize_query('alertlist', { hostname: 'web01', statetypes: 'HARD' }, context)
      expect(res[:data][:alertlist].size).to eq(2)
      expect(res[:data][:alertlist].first[:host_name]).to eq('web01')
      expect(res[:data][:alertlist].first[:state_type]).to eq('HARD')
    end

    it 'handles notificationcount and notificationlist' do
      count_res = serializer.serialize_query('notificationcount', {}, context)
      expect(count_res[:data][:count][:total]).to eq(1)

      list_res = serializer.serialize_query('notificationlist', { contact: 'alice' }, context)
      expect(list_res[:data][:notificationlist].size).to eq(1)
      expect(list_res[:data][:notificationlist].first[:contact_name]).to eq('alice')
    end

    it 'handles pagination via start and count' do
      res = serializer.serialize_query('alertlist', { start: 1, count: 1 }, context)
      expect(res[:data][:alertlist].size).to eq(1)
      expect(res[:data][:alertlist].first[:service_description]).to eq('HTTP')
    end

    it 'handles availability query' do
      res = serializer.serialize_query('availability', {}, context)
      expect(res[:data][:availability][:hosts]['web01'][:percent_known]).to eq(100.0)
      expect(res[:data][:availability][:services]['web01:HTTP'][:percent_ok]).to be > 90.0
    end

    it 'returns option_invalid error for unknown queries' do
      res = serializer.serialize_query('nonexistent_query', {}, context)
      expect(res[:result][:type_code]).to eq(3)
      expect(res[:result][:type_text]).to eq('Option Invalid')
    end
  end
end
