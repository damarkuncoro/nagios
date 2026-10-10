# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::UseCases::VerifyConfiguration do
  let(:mock_engine) { class_double(Engines::NagiosEngine) }
  subject(:use_case) { described_class.new(engine: mock_engine) }

  before do
    allow(mock_engine).to receive(:commands).and_return([
      { 'name' => 'check-host-alive', 'command_line' => '$USER1$/check_ping' },
      { 'name' => 'check_ping', 'command_line' => '$USER1$/check_ping' },
      { 'name' => 'check_http', 'command_line' => '$USER1$/check_http' }
    ])
    allow(mock_engine).to receive(:timeperiods).and_return([
      { 'name' => '24x7', 'alias' => '24 Hours A Day' }
    ])
    allow(mock_engine).to receive(:host_objects).and_return({
      'localhost' => {
        'name' => 'localhost',
        'check_command' => 'check-host-alive',
        'check_period' => '24x7',
        'parent_hosts' => []
      }
    })
    allow(mock_engine).to receive(:service_objects).and_return({
      'localhost' => {
        'HTTP' => {
          'description' => 'HTTP',
          'check_command' => 'check_http',
          'check_period' => '24x7'
        }
      }
    })
  end

  describe '#call' do
    context 'when configuration is fully valid' do
      it 'returns a passing result with 0 errors and 0 warnings' do
        result = use_case.call

        expect(result.valid?).to be true
        expect(result.errors).to be_empty
        expect(result.warnings).to be_empty
        expect(result.metrics[:hosts_checked]).to eq(1)
        expect(result.metrics[:services_checked]).to eq(1)
        expect(result.metrics[:commands_checked]).to eq(3)
        expect(result.metrics[:circular_loops_detected]).to eq(0)
        expect(result.summary).to include("Things look okay")
      end
    end

    context 'when an undefined check_command is referenced' do
      before do
        allow(mock_engine).to receive(:service_objects).and_return({
          'localhost' => {
            'Custom App' => {
              'description' => 'Custom App',
              'check_command' => 'check_missing_script!arg1',
              'check_period' => '24x7'
            }
          }
        })
      end

      it 'captures verification error and marks result invalid' do
        result = use_case.call

        expect(result.valid?).to be false
        expect(result.errors.size).to eq(1)
        expect(result.errors.first).to include("references undefined check_command 'check_missing_script'")
      end
    end

    context 'when an orphan service references a non-existent host' do
      before do
        allow(mock_engine).to receive(:service_objects).and_return({
          'unknown_host' => {
            'PING' => {
              'description' => 'PING',
              'check_command' => 'check_ping'
            }
          }
        })
      end

      it 'captures orphan service error' do
        result = use_case.call

        expect(result.valid?).to be false
        expect(result.errors.first).to include("references undefined host 'unknown_host'")
      end
    end

    context 'when a circular dependency exists in host hierarchy' do
      before do
        allow(mock_engine).to receive(:host_objects).and_return({
          'router-a' => { 'name' => 'router-a', 'check_command' => 'check-host-alive', 'parent_hosts' => ['router-b'] },
          'router-b' => { 'name' => 'router-b', 'check_command' => 'check-host-alive', 'parent_hosts' => ['router-a'] }
        })
        allow(mock_engine).to receive(:service_objects).and_return({})
      end

      it 'detects circular host loop and marks result invalid' do
        result = use_case.call

        expect(result.valid?).to be false
        expect(result.metrics[:circular_loops_detected]).to be >= 1
        expect(result.errors.any? { |e| e.include?("Circular path detected between hosts") }).to be true
      end
    end

    context 'when an undefined timeperiod is referenced' do
      before do
        allow(mock_engine).to receive(:host_objects).and_return({
          'localhost' => {
            'name' => 'localhost',
            'check_command' => 'check-host-alive',
            'check_period' => 'non_existent_schedule',
            'parent_hosts' => []
          }
        })
      end

      it 'adds a warning but allows valid if no errors' do
        result = use_case.call

        expect(result.valid?).to be true
        expect(result.warnings.size).to eq(1)
        expect(result.warnings.first).to include("references undefined timeperiod 'non_existent_schedule'")
      end
    end
  end
end
