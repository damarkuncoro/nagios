# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::StatusJsonSerializer do
  let(:serializer) { described_class.new }

  let(:context) do
    {
      hosts: [
        { name: 'web01', status: 'UP', plugin_output: 'HTTP OK' },
        { name: 'db01', status: 'DOWN', plugin_output: 'Connection timeout' }
      ],
      services: [
        { host_name: 'web01', description: 'HTTP', status: 'OK' },
        { host_name: 'db01', description: 'MySQL', status: 'CRITICAL' }
      ],
      program_status: {
        version: '4.5.12',
        is_currently_running: true
      },
      downtimes: [
        { id: '1', host_name: 'db01', author: 'admin', comment: 'Upgrading' }
      ],
      comments: [
        { id: '10', host_name: 'web01', author: 'alice', data: 'Investigation ongoing' }
      ],
      user: 'nagiosadmin'
    }
  end

  describe '#serialize_query' do
    it 'serializes hostcount query with standard envelope' do
      res = serializer.serialize_query('hostcount', {}, context)

      expect(res[:format_version]).to eq(0)
      expect(res[:result][:cgi]).to eq('statusjson.cgi')
      expect(res[:result][:query]).to eq('hostcount')
      expect(res[:result][:type_code]).to eq(0)
      expect(res[:result][:type_text]).to eq('Success')
      expect(res[:data][:count][:total]).to eq(2)
      expect(res[:data][:count][:up]).to eq(1)
      expect(res[:data][:count][:down]).to eq(1)
    end

    it 'serializes servicecount query' do
      res = serializer.serialize_query('servicecount', {}, context)

      expect(res[:data][:count][:total]).to eq(2)
      expect(res[:data][:count][:ok]).to eq(1)
      expect(res[:data][:count][:critical]).to eq(1)
    end

    it 'serializes hostlist query' do
      res = serializer.serialize_query('hostlist', {}, context)

      expect(res[:data][:hostlist].keys).to contain_exactly('web01', 'db01')
      expect(res[:data][:hostlist]['web01'][:status]).to eq('UP')
    end

    it 'serializes servicelist query' do
      res = serializer.serialize_query('servicelist', {}, context)

      expect(res[:data][:servicelist]['web01']['HTTP'][:status]).to eq('OK')
    end

    it 'serializes programstatus query' do
      res = serializer.serialize_query('programstatus', {}, context)

      expect(res[:data][:programstatus][:version]).to eq('4.5.12')
      expect(res[:data][:programstatus][:is_currently_running]).to be true
    end

    it 'serializes downtimelist query' do
      res = serializer.serialize_query('downtimelist', {}, context)

      expect(res[:data][:downtimelist]['1'][:author]).to eq('admin')
    end

    it 'handles unknown query with option_invalid error code' do
      res = serializer.serialize_query('nonexistent_query', {}, context)

      expect(res[:result][:type_code]).to eq(3) # Option Invalid
      expect(res[:result][:type_text]).to eq('Option Invalid')
      expect(res[:result][:message]).to include('Unknown query')
    end
  end
end
