# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::ExternalCommandHandler do
  let(:handler) { described_class.new }

  describe '#process' do
    context 'empty commands' do
      it 'returns error result when command line is empty' do
        result = handler.process('')
        expect(result.success?).to be false
        expect(result.message).to include('empty')
      end

      it 'returns error result for unknown command' do
        result = handler.process('[1700000000] UNKNOWN_COMMAND;arg1')
        expect(result.success?).to be false
        expect(result.message).to include('Unknown or unsupported')
      end
    end

    context 'passive check results' do
      it 'handles PROCESS_SERVICE_CHECK_RESULT with perfdata' do
        cmd = '[1700000000] PROCESS_SERVICE_CHECK_RESULT;srv-db01;MySQL Status;0;OK - DB running smooth|connections=42;100;200'
        result = handler.process(cmd)

        expect(result.success?).to be true
        expect(result.command).to eq('PROCESS_SERVICE_CHECK_RESULT')
        expect(result.entry_time).to eq(1700000000)
        expect(result.data[:host]).to eq('srv-db01')
        expect(result.data[:service]).to eq('MySQL Status')
        expect(result.data[:return_code]).to eq(0)
        expect(result.data[:perfdata].metrics).to be_an(Array)
        expect(result.data[:perfdata].metrics.first.label).to eq('connections')
        expect(result.data[:perfdata].metrics.first.value).to eq(42.0)
      end

      it 'handles PROCESS_HOST_CHECK_RESULT' do
        cmd = 'PROCESS_HOST_CHECK_RESULT;web01;0;PING OK - Packet loss 0%|rta=0.12ms'
        result = handler.process(cmd)

        expect(result.success?).to be true
        expect(result.command).to eq('PROCESS_HOST_CHECK_RESULT')
        expect(result.data[:host]).to eq('web01')
        expect(result.data[:return_code]).to eq(0)
      end
    end

    context 'check scheduling' do
      it 'handles SCHEDULE_FORCED_SVC_CHECK' do
        cmd = '[1700000000] SCHEDULE_FORCED_SVC_CHECK;srv01;HTTP;1700000060'
        result = handler.process(cmd)

        expect(result.success?).to be true
        expect(result.data[:host]).to eq('srv01')
        expect(result.data[:service]).to eq('HTTP')
        expect(result.data[:check_time]).to eq(1700000060)
      end

      it 'handles SCHEDULE_FORCED_HOST_CHECK' do
        cmd = '[1700000000] SCHEDULE_FORCED_HOST_CHECK;srv01;1700000060'
        result = handler.process(cmd)

        expect(result.success?).to be true
        expect(result.data[:host]).to eq('srv01')
        expect(result.data[:check_time]).to eq(1700000060)
      end
    end

    context 'acknowledgements' do
      it 'handles ACKNOWLEDGE_SVC_PROBLEM and REMOVE_SVC_ACKNOWLEDGEMENT' do
        ack_cmd = '[1700000000] ACKNOWLEDGE_SVC_PROBLEM;srv01;Disk Space;2;1;1;nagiosadmin;Investigating disk saturation'
        ack_res = handler.process(ack_cmd)

        expect(ack_res.success?).to be true
        expect(ack_res.data[:author]).to eq('nagiosadmin')
        expect(ack_res.data[:comment]).to eq('Investigating disk saturation')

        remove_cmd = '[1700000000] REMOVE_SVC_ACKNOWLEDGEMENT;srv01;Disk Space'
        rm_res = handler.process(remove_cmd)
        expect(rm_res.success?).to be true
        expect(rm_res.message).to include('removed')
      end

      it 'handles ACKNOWLEDGE_HOST_PROBLEM' do
        ack_cmd = '[1700000000] ACKNOWLEDGE_HOST_PROBLEM;srv01;2;1;1;sre_lead;Power supply replacement'
        ack_res = handler.process(ack_cmd)

        expect(ack_res.success?).to be true
        expect(ack_res.data[:author]).to eq('sre_lead')
      end
    end

    context 'downtime scheduling' do
      it 'handles SCHEDULE_SVC_DOWNTIME and DEL_SVC_DOWNTIME' do
        down_cmd = '[1700000000] SCHEDULE_SVC_DOWNTIME;srv01;SSH;1700000000;1700003600;1;0;3600;admin;Kernel upgrade'
        down_res = handler.process(down_cmd)

        expect(down_res.success?).to be true
        expect(down_res.data[:downtime_id]).to be_a(Integer)
        expect(down_res.data[:duration]).to eq(3600)

        del_cmd = "[1700000000] DEL_SVC_DOWNTIME;#{down_res.data[:downtime_id]}"
        del_res = handler.process(del_cmd)
        expect(del_res.success?).to be true
        expect(del_res.data[:downtime_id]).to eq(down_res.data[:downtime_id])
      end
    end

    context 'feature toggles' do
      it 'handles notifications and flap detection toggles' do
        expect(handler.process('ENABLE_NOTIFICATIONS').success?).to be true
        expect(handler.process('DISABLE_NOTIFICATIONS').success?).to be true
        expect(handler.process('ENABLE_FLAP_DETECTION').success?).to be true
        expect(handler.process('DISABLE_FLAP_DETECTION').success?).to be true
        expect(handler.process('ENABLE_SVC_NOTIFICATIONS;srv01;HTTP').success?).to be true
        expect(handler.process('DISABLE_SVC_NOTIFICATIONS;srv01;HTTP').success?).to be true
        expect(handler.process('ENABLE_SVC_FLAP_DETECTION;srv01;HTTP').success?).to be true
      end
    end

    context 'comments and retention commands' do
      it 'handles ADD_SVC_COMMENT and DEL_SVC_COMMENT' do
        add_res = handler.process('[1700000000] ADD_SVC_COMMENT;srv01;HTTP;1;admin;Checking latency spike')
        expect(add_res.success?).to be true
        expect(add_res.data[:comment_id]).to be_a(Integer)

        del_res = handler.process("[1700000000] DEL_SVC_COMMENT;#{add_res.data[:comment_id]}")
        expect(del_res.success?).to be true
      end

      it 'handles SAVE_STATE_INFORMATION and READ_STATE_INFORMATION' do
        expect(handler.process('SAVE_STATE_INFORMATION').success?).to be true
        expect(handler.process('READ_STATE_INFORMATION').success?).to be true
      end
    end
  end

  describe '.process_batch' do
    it 'processes array of command lines sequentially' do
      cmds = [
        'ENABLE_NOTIFICATIONS',
        'PROCESS_HOST_CHECK_RESULT;host1;0;OK',
        'DISABLE_NOTIFICATIONS'
      ]
      results = described_class.process_batch(cmds)
      expect(results.size).to eq(3)
      expect(results.all?(&:success?)).to be true
    end
  end
end
