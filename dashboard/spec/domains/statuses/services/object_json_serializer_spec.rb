# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::ObjectJsonSerializer do
  let(:serializer) { described_class.new }

  let(:context) do
    {
      hosts: [
        { name: 'web01', alias: 'Web Server 1', address: '10.0.0.1', check_command: 'check_ping', max_attempts: 3 },
        { name: 'db01', alias: 'DB Primary', address: '10.0.0.2', check_command: 'check_ssh', max_attempts: 5 }
      ],
      services: [
        { host_name: 'web01', description: 'HTTP', check_command: 'check_http', max_attempts: 3 },
        { host_name: 'db01', description: 'MySQL', check_command: 'check_tcp!3306', max_attempts: 4 }
      ],
      hostgroups: [
        { name: 'web-servers', alias: 'Web Farm', members: ['web01'] }
      ],
      servicegroups: [
        { name: 'core-services', alias: 'Core Services', members: ['HTTP', 'MySQL'] }
      ],
      contacts: [
        { name: 'alice', alias: 'Alice SRE', email: 'alice@example.com' }
      ],
      contactgroups: [
        { name: 'oncall-team', alias: 'On-Call', members: ['alice'] }
      ],
      timeperiods: [
        { name: '24x7', alias: '24 Hours A Day, 7 Days A Week' }
      ],
      commands: [
        { name: 'check_ping', line: '$USER1$/check_ping -H $HOSTADDRESS$' }
      ],
      user: 'nagiosadmin'
    }
  end

  describe '#serialize_query' do
    it 'serializes hostcount and hostlist queries' do
      count_res = serializer.serialize_query('hostcount', {}, context)
      expect(count_res[:format_version]).to eq(0)
      expect(count_res[:result][:cgi]).to eq('objectjson.cgi')
      expect(count_res[:data][:count][:total]).to eq(2)

      list_res = serializer.serialize_query('hostlist', {}, context)
      expect(list_res[:data][:hostlist]['web01'][:address]).to eq('10.0.0.1')
    end

    it 'serializes specific single host query' do
      host_res = serializer.serialize_query('host', { host: 'web01' }, context)
      expect(host_res[:data][:host][:name]).to eq('web01')

      missing_res = serializer.serialize_query('host', { host: 'unknown_host' }, context)
      expect(missing_res[:result][:type_code]).to eq(6) # Option Value Invalid
    end

    it 'serializes servicecount and servicelist queries' do
      list_res = serializer.serialize_query('servicelist', {}, context)
      expect(list_res[:data][:servicelist]['web01']['HTTP'][:check_command]).to eq('check_http')
    end

    it 'serializes hostgrouplist and servicegrouplist queries' do
      hg_res = serializer.serialize_query('hostgrouplist', {}, context)
      expect(hg_res[:data][:hostgrouplist]['web-servers'][:members]).to eq(['web01'])

      sg_res = serializer.serialize_query('servicegrouplist', {}, context)
      expect(sg_res[:data][:servicegrouplist]['core-services'][:members]).to eq(%w[HTTP MySQL])
    end

    it 'serializes contacts, contactgroups, timeperiods, and commands' do
      c_res = serializer.serialize_query('contactlist', {}, context)
      expect(c_res[:data][:contactlist]['alice'][:email]).to eq('alice@example.com')

      tp_res = serializer.serialize_query('timeperiodlist', {}, context)
      expect(tp_res[:data][:timeperiodlist]['24x7'][:alias]).to include('24 Hours')

      cmd_res = serializer.serialize_query('commandlist', {}, context)
      expect(cmd_res[:data][:commandlist]['check_ping'][:line]).to include('check_ping')
    end

    it 'returns option_invalid error on unrecognized query' do
      err_res = serializer.serialize_query('unknown_object_query', {}, context)
      expect(err_res[:result][:type_code]).to eq(3)
    end
  end
end
