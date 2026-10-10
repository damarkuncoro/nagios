# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::StatusDataParser do
  let(:sample_status_dat) do
    <<~DAT
      info {
      \tcreated=1700000000
      \tversion=4.4.6
      }

      programstatus {
      \tnagios_pid=1234
      \tprogram_start=1699990000
      \tnotifications_enabled=1
      \tchecks_enabled=1
      }

      hoststatus {
      \thost_name=web-server-01
      \tcurrent_state=0
      \tplugin_output=PING OK - Packet loss 0%
      \tperf_data=rta=0.045ms;100;500
      \tcurrent_attempt=1
      \tmax_attempts=3
      \tnotifications_enabled=1
      \tscheduled_downtime_depth=0
      \tpercent_state_change=0.0
      }

      hoststatus {
      \thost_name=db-master-01
      \tcurrent_state=1
      \tplugin_output=CRITICAL - Host Unreachable
      \tscheduled_downtime_depth=1
      }

      servicestatus {
      \thost_name=web-server-01
      \tservice_description=HTTP Health
      \tcurrent_state=0
      \tplugin_output=HTTP OK: HTTP/1.1 200 OK
      \texecution_time=0.035
      }

      servicestatus {
      \thost_name=web-server-01
      \tservice_description=Disk Root
      \tcurrent_state=2
      \tplugin_output=DISK CRITICAL - free space: / 2%
      \texecution_time=0.012
      }

      hostcomment {
      \thost_name=db-master-01
      \tcomment_id=501
      \tentry_type=1
      \tauthor=nagiosadmin
      \tcomment_data=Investigating power failure
      }

      hostdowntime {
      \thost_name=db-master-01
      \tdowntime_id=901
      \tstart_time=1700000000
      \tend_time=1700003600
      \tduration=3600
      \tfixed=1
      \tauthor=sre_team
      \tcomment=Emergency database reboot
      }
    DAT
  end

  describe '#parse' do
    it 'parses all status blocks correctly' do
      snapshot = described_class.parse(sample_status_dat)

      expect(snapshot.info['version']).to eq('4.4.6')
      expect(snapshot.programstatus['nagios_pid']).to eq(1234)
      expect(snapshot.host_count).to eq(2)
      expect(snapshot.service_count).to eq(2)

      # Host status checks
      web = snapshot.hosts['web-server-01']
      expect(web['current_state']).to eq(0)
      expect(web['plugin_output']).to eq('PING OK - Packet loss 0%')
      expect(web['current_attempt']).to eq(1)

      db = snapshot.hosts['db-master-01']
      expect(db['current_state']).to eq(1)
      expect(db['scheduled_downtime_depth']).to eq(1)

      # Service status checks
      http = snapshot.services.dig('web-server-01', 'HTTP Health')
      expect(http['current_state']).to eq(0)
      expect(http['execution_time']).to eq(0.035)

      disk = snapshot.services.dig('web-server-01', 'Disk Root')
      expect(disk['current_state']).to eq(2)

      # Problem hosts & services helpers
      expect(snapshot.problem_hosts.size).to eq(1)
      expect(snapshot.problem_services.size).to eq(1)

      # Comments and downtimes
      expect(snapshot.comments.size).to eq(1)
      expect(snapshot.comments.first['comment_id']).to eq(501)
      expect(snapshot.comments.first['author']).to eq('nagiosadmin')

      expect(snapshot.downtimes.size).to eq(1)
      expect(snapshot.downtimes.first['downtime_id']).to eq(901)
      expect(snapshot.downtimes.first['duration']).to eq(3600)
    end

    it 'returns empty snapshot for blank content' do
      snapshot = described_class.parse('')
      expect(snapshot.host_count).to eq(0)
      expect(snapshot.service_count).to eq(0)
      expect(snapshot.comments).to be_empty
    end
  end

  describe '#serialize' do
    it 'serializes snapshot and supports roundtrip parsing' do
      original = described_class.parse(sample_status_dat)
      serialized = described_class.serialize(original)

      expect(serialized).to include('info {')
      expect(serialized).to include('programstatus {')
      expect(serialized).to include('hoststatus {')
      expect(serialized).to include('servicestatus {')
      expect(serialized).to include('hostcomment {')
      expect(serialized).to include('hostdowntime {')

      # Roundtrip
      reparsed = described_class.parse(serialized)
      expect(reparsed.host_count).to eq(original.host_count)
      expect(reparsed.service_count).to eq(original.service_count)
      expect(reparsed.comments.size).to eq(original.comments.size)
      expect(reparsed.downtimes.size).to eq(original.downtimes.size)
    end
  end
end
