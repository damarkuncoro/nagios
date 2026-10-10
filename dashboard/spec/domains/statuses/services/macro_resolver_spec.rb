# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::MacroResolver do
  describe '.macros' do
    it 'returns defined $USERx$ macros map' do
      macros = described_class.macros
      expect(macros).to be_a(Hash)
      expect(macros).to have_key('$USER1$')
      expect(macros['$USER1$']).to be_present
    end
  end

  describe '.resolve' do
    it 'returns empty string for blank template' do
      expect(described_class.resolve(nil)).to eq('')
      expect(described_class.resolve('')).to eq('')
    end

    it 'resolves $USER1$ plugin directory macro' do
      cmd = '$USER1$/check_ping -H 127.0.0.1'
      resolved = described_class.resolve(cmd)
      expect(resolved).not_to include('$USER1$')
      expect(resolved).to include('/check_ping -H 127.0.0.1')
    end

    it 'resolves $HOSTNAME$ and $HOSTADDRESS$' do
      cmd = '$USER1$/check_ping -H $HOSTADDRESS$ -w 100,20% -c 500,60%'
      host = double(name: 'web-prod-01', address: '192.168.1.100')
      resolved = described_class.resolve(cmd, host: host)

      expect(resolved).to include('-H 192.168.1.100')
      expect(resolved).not_to include('$HOSTADDRESS$')
    end

    it 'resolves $SERVICEDESC$ and $ARGx$ parameters' do
      cmd = '$USER1$/check_http -H $HOSTADDRESS$ -u $ARG1$ -p $ARG2$'
      host = { 'name' => 'api-server', 'address' => '10.0.0.5' }
      service = { 'description' => 'API Health' }
      resolved = described_class.resolve(cmd, host: host, service: service, bang_args: ['/healthz', '8080'])

      expect(resolved).to include('-H 10.0.0.5')
      expect(resolved).to include('-u /healthz -p 8080')
      expect(resolved).not_to include('$ARG1$')
      expect(resolved).not_to include('$ARG2$')
    end

    it 'resolves state macros and IDs for host and service' do
      tpl = 'HOST=$HOSTNAME$ STATE=$HOSTSTATE$ ($HOSTSTATEID$) SVC=$SERVICEDESC$ STATE=$SERVICESTATE$ ($SERVICESTATEID$)'
      host = { name: 'db-master', status: 'DOWN' }
      service = { description: 'Replication Lag', status: 'CRITICAL' }

      resolved = described_class.resolve(tpl, host: host, service: service)
      expect(resolved).to eq('HOST=db-master STATE=DOWN (1) SVC=Replication Lag STATE=CRITICAL (2)')
    end

    it 'resolves date and notification macros' do
      tpl = 'DATE=$DATE$ TIME=$TIME$ NOTIF=$NOTIFICATIONTYPE$ CONTACT=$CONTACTNAME$ EMAIL=$CONTACTEMAIL$'
      notif = { type: 'PROBLEM' }
      contact = { name: 'sysadmin', email: 'ops@company.internal' }

      resolved = described_class.resolve(tpl, notification: notif, contact: contact)
      expect(resolved).to include('NOTIF=PROBLEM')
      expect(resolved).to include('CONTACT=sysadmin')
      expect(resolved).to include('EMAIL=ops@company.internal')
      expect(resolved).not_to include('$DATE$')
      expect(resolved).not_to include('$TIME$')
    end
  end
end
