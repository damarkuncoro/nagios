# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Standalone Pure-Ruby Engine Architecture' do
  let(:sample_cfg) { File.read(Rails.root.join('config/nagios_sample.cfg')) }
  let(:catalog) { Statuses::Services::ObjectConfigParser.parse(sample_cfg) }
  let(:mutex) { Mutex.new }
  let(:event_queue) { Statuses::Services::TimedEventQueue.new }
  let(:worker_pool) { Statuses::Services::WorkerProcessPool.new(max_workers: 2) }

  describe Engines::StatusDumper do
    let(:tmp_file) { Rails.root.join('tmp/test_status.dat').to_s }

    after { File.unlink(tmp_file) rescue nil }

    it 'atomically serializes and writes a valid Nagios status.dat file' do
      host_states = {
        'localhost' => { 'host_name' => 'localhost', 'current_state' => 0, 'plugin_output' => 'OK' }
      }
      service_states = {
        'localhost' => {
          'HTTP' => { 'service_description' => 'HTTP', 'current_state' => 0, 'plugin_output' => 'HTTP OK' }
        }
      }

      Engines::StatusDumper.dump!(
        target_file: tmp_file,
        start_time: Time.now.to_i - 100,
        active_workers: 0,
        host_states: host_states,
        service_states: service_states,
        comments: [],
        downtimes: [],
        notifications_enabled: 1,
        mutex: mutex
      )

      expect(File.exist?(tmp_file)).to be true
      content = File.read(tmp_file)
      expect(content).to include('info {')
      expect(content).to include('programstatus {')
      expect(content).to include('hoststatus {')
      expect(content).to include('servicestatus {')
      expect(content).to include('host_name=localhost')
      expect(content).to include('service_description=HTTP')
    end
  end

  describe Engines::ExternalCommandApplier do
    let(:host_states) { {} }
    let(:service_states) { {} }
    let(:comments) { [] }
    let(:downtimes) { [] }
    let(:applier) do
      described_class.new(
        config_catalog: catalog,
        event_queue: event_queue,
        host_states: host_states,
        service_states: service_states,
        comments: comments,
        downtimes: downtimes,
        mutex: mutex,
        notifications_enabled: 1
      )
    end

    it 'handles RELOAD_CONFIG by requesting reload' do
      parsed = Statuses::Services::ExternalCommandHandler.process('[12345] RELOAD_CONFIG')
      reload_req, state_mod = applier.apply!(parsed)

      expect(reload_req).to be true
      expect(state_mod).to be false
    end

    it 'schedules immediate service check into event queue' do
      parsed = Statuses::Services::ExternalCommandHandler.process('[12345] SCHEDULE_SVC_CHECK;localhost;HTTP Endpoint Health;12345')
      _reload_req, _state_mod = applier.apply!(parsed)

      expect(event_queue.size).to eq(1)
      due = event_queue.process_due(Time.now.to_i + 1)
      expect(due.first.target).to eq('localhost/HTTP Endpoint Health')
    end

    it 'applies passive service check results and mutates state' do
      cmd = '[12345] PROCESS_SERVICE_CHECK_RESULT;localhost;HTTP Endpoint Health;2;HTTP CRITICAL - Connection Refused|time=0.5s;1.0;2.0'
      parsed = Statuses::Services::ExternalCommandHandler.process(cmd)
      reload_req, state_mod = applier.apply!(parsed)

      expect(reload_req).to be false
      expect(state_mod).to be true
      svc = service_states.dig('localhost', 'HTTP Endpoint Health')
      expect(svc).not_to be_nil
      expect(svc['current_state']).to eq(2)
      expect(svc['plugin_output']).to include('HTTP CRITICAL')
      expect(svc['perf_data']).to include('time=0.5s')
    end

    it 'applies passive host check results and mutates state' do
      cmd = '[12345] PROCESS_HOST_CHECK_RESULT;gateway;1;HOST DOWN - Ping timeout|rta=0ms;500;1000'
      parsed = Statuses::Services::ExternalCommandHandler.process(cmd)
      _reload_req, state_mod = applier.apply!(parsed)

      expect(state_mod).to be true
      host = host_states['gateway']
      expect(host).not_to be_nil
      expect(host['current_state']).to eq(1)
      expect(host['plugin_output']).to include('HOST DOWN')
    end

    it 'acknowledges service problem and creates persistent comment' do
      service_states['localhost'] = {
        'Root Disk Usage' => { 'current_state' => 2, 'problem_has_been_acknowledged' => 0 }
      }
      cmd = '[12345] ACKNOWLEDGE_SVC_PROBLEM;localhost;Root Disk Usage;1;1;1;ops_team;Disk cleanup in progress'
      parsed = Statuses::Services::ExternalCommandHandler.process(cmd)
      _reload_req, state_mod = applier.apply!(parsed)

      expect(state_mod).to be true
      expect(service_states['localhost']['Root Disk Usage']['problem_has_been_acknowledged']).to eq(1)
      expect(comments.size).to eq(1)
      expect(comments.first['author']).to eq('ops_team')
      expect(comments.first['comment_data']).to eq('Disk cleanup in progress')
    end

    it 'schedules and deletes service downtime' do
      now = Time.now.to_i
      cmd = "[12345] SCHEDULE_SVC_DOWNTIME;localhost;Root Disk Usage;#{now};#{now + 3600};1;0;3600;admin;Maintenance window"
      parsed = Statuses::Services::ExternalCommandHandler.process(cmd)
      _reload_req, state_mod = applier.apply!(parsed)

      expect(state_mod).to be true
      expect(downtimes.size).to eq(1)
      dt_id = downtimes.first['downtime_id']
      expect(downtimes.first['author']).to eq('admin')

      del_cmd = "[12345] DEL_SVC_DOWNTIME;#{dt_id}"
      del_parsed = Statuses::Services::ExternalCommandHandler.process(del_cmd)
      applier.apply!(del_parsed)
      expect(downtimes).to be_empty
    end

    it 'toggles notification enable flag' do
      expect(applier.notifications_enabled).to eq(1)
      applier.apply!(Statuses::Services::ExternalCommandHandler.process('[12345] DISABLE_NOTIFICATIONS'))
      expect(applier.notifications_enabled).to eq(0)
      applier.apply!(Statuses::Services::ExternalCommandHandler.process('[12345] ENABLE_NOTIFICATIONS'))
      expect(applier.notifications_enabled).to eq(1)
    end
  end

  describe Engines::CheckExecutor do
    let(:host_states) { {} }
    let(:service_states) { {} }
    let(:host_histories) { {} }
    let(:service_histories) { {} }
    let(:log_file) { Rails.root.join('tmp/test_nagios.log').to_s }
    let(:executor) do
      described_class.new(
        config_catalog: catalog,
        worker_pool: worker_pool,
        host_states: host_states,
        service_states: service_states,
        host_histories: host_histories,
        service_histories: service_histories,
        mutex: mutex,
        log_file_path: log_file
      )
    end

    after { File.unlink(log_file) rescue nil }

    it 'updates catalog cleanly without error' do
      expect { executor.update_catalog!(catalog) }.not_to raise_error
    end
  end

  describe Engines::StandaloneDaemon do
    let(:options) do
      {
        config_file: Rails.root.join('config/nagios_sample.cfg').to_s,
        status_file: Rails.root.join('tmp/test_daemon_status.dat').to_s,
        log_file: Rails.root.join('tmp/test_daemon.log').to_s,
        pid_file: Rails.root.join('tmp/test_daemon.pid').to_s,
        workers: 2,
        verify_only: true
      }
    end
    let(:daemon) { described_class.new(options) }

    it 'initializes properly with subcomponents and paths' do
      expect(daemon.status_file_path).to eq(options[:status_file])
      expect(daemon.log_file_path).to eq(options[:log_file])
      expect(daemon.pid_file_path).to eq(options[:pid_file])
      expect(daemon.check_executor).to be_a(Engines::CheckExecutor)
      expect(daemon.command_applier).to be_a(Engines::ExternalCommandApplier)
    end

    it 'performs configuration verification run without exceptions' do
      expect { daemon.run! }.not_to raise_error
      expect(daemon.config_catalog.hosts.size).to eq(2)
      expect(daemon.config_catalog.services.size).to eq(7)
    end
  end
end
