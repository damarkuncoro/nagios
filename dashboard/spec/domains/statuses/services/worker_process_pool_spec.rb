# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Statuses::Services::WorkerProcessPool do
  let(:pool) { described_class.new(max_workers: 4) }

  describe '#run_job' do
    it 'runs command and returns 0 for OK' do
      res = pool.run_job("echo 'ALL OK'")
      expect(res.ok?).to be true
      expect(res.exit_code).to eq(0)
      expect(res.status_name).to eq('OK')
      expect(res.output).to eq('ALL OK')
      expect(res.execution_time).to be >= 0.0
    end

    it 'captures non-zero exit code matching Nagios status codes' do
      res = pool.run_job("sh -c 'echo CRITICAL ERROR; exit 2'")
      expect(res.critical?).to be true
      expect(res.exit_code).to eq(2)
      expect(res.status_name).to eq('CRITICAL')
      expect(res.output).to eq('CRITICAL ERROR')
    end

    it 'enforces timeout and returns UNKNOWN (3)' do
      res = pool.run_job("sh -c 'sleep 2; echo done'", timeout: 0.1)
      expect(res.timed_out?).to be true
      expect(res.unknown?).to be true
      expect(res.exit_code).to eq(3)
      expect(res.output).to include('Plugin timed out')
    end
  end

  describe '#stats' do
    it 'tracks completed jobs and worker limits' do
      pool.run_job("echo 'job 1'")
      pool.run_job("echo 'job 2'")

      stats = pool.stats
      expect(stats[:total_jobs_run]).to eq(2)
      expect(stats[:max_workers]).to eq(4)
      expect(stats[:active_workers]).to eq(0)
    end
  end
end
