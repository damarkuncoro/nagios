# frozen_string_literal: true

require 'open3'
require 'timeout'

module Statuses
  module Services
    # Adopts worker process pool and job execution from base/workers.c
    # Spawns check commands and event handlers with timeout protection and Nagios exit code mapping.
    class WorkerProcessPool
      DEFAULT_TIMEOUT = 10.0
      MAX_WORKERS = 16

      JobResult = Struct.new(
        :exit_code,
        :status_name,
        :output,
        :stderr,
        :execution_time,
        :timed_out,
        keyword_init: true
      ) do
        def ok?
          exit_code == 0
        end

        def warning?
          exit_code == 1
        end

        def critical?
          exit_code == 2
        end

        def unknown?
          exit_code >= 3
        end

        def timed_out?
          timed_out == true
        end
      end

      STATUS_NAMES = {
        0 => 'OK',
        1 => 'WARNING',
        2 => 'CRITICAL',
        3 => 'UNKNOWN'
      }.freeze

      def initialize(max_workers: MAX_WORKERS)
        @max_workers = max_workers
        @active_workers = 0
        @total_jobs_run = 0
        @mutex = Mutex.new
      end

      # Executes check or event handler job with timeout protection (base/workers.c wproc_run_job)
      def run_job(command_line, timeout: DEFAULT_TIMEOUT)
        return timeout_result(timeout) if command_line.to_s.strip.empty?

        @mutex.synchronize do
          @active_workers += 1
          @total_jobs_run += 1
        end

        t_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        stdout_str = ''
        stderr_str = ''
        exit_code = 3
        timed_out = false

        begin
          Timeout.timeout(timeout) do
            Open3.popen3(command_line) do |_stdin, stdout, stderr, wait_thr|
              stdout_str = stdout.read.to_s
              stderr_str = stderr.read.to_s
              status = wait_thr.value
              exit_code = status.exitstatus || 3
            end
          end
        rescue Timeout::Error
          timed_out = true
          exit_code = 3 # UNKNOWN
          stdout_str = "CRITICAL - Plugin timed out after #{timeout} seconds"
        rescue StandardError => e
          exit_code = 3
          stderr_str = e.message
          stdout_str = "UNKNOWN - Execution failed: #{e.message}"
        ensure
          @mutex.synchronize { @active_workers -= 1 }
        end

        t_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        exec_time = (t_end - t_start).round(3)

        norm_code = normalize_exit_code(exit_code)

        JobResult.new(
          exit_code: norm_code,
          status_name: STATUS_NAMES[norm_code] || 'UNKNOWN',
          output: stdout_str.strip,
          stderr: stderr_str.strip,
          execution_time: exec_time,
          timed_out: timed_out
        )
      end

      # Returns worker pool health and statistics
      def stats
        @mutex.synchronize do
          {
            max_workers: @max_workers,
            active_workers: @active_workers,
            available_slots: [@max_workers - @active_workers, 0].max,
            total_jobs_run: @total_jobs_run
          }
        end
      end

      private

      def normalize_exit_code(code)
        c = code.to_i
        c.between?(0, 3) ? c : 3
      end

      def timeout_result(timeout)
        JobResult.new(
          exit_code: 3,
          status_name: 'UNKNOWN',
          output: 'UNKNOWN - Empty command provided',
          stderr: '',
          execution_time: 0.0,
          timed_out: false
        )
      end
    end
  end
end
