# frozen_string_literal: true

require 'fileutils'

module Engines
  # Pure-Ruby Standalone Monitoring Engine Orchestrator
  class StandaloneDaemon
    attr_reader :options, :config_catalog, :event_queue, :worker_pool,
                :coordinator, :running, :check_executor, :command_applier

    def initialize(options = {})
      @options = options
      @running = false
      @event_queue = Statuses::Services::TimedEventQueue.new
      @worker_pool = Statuses::Services::WorkerProcessPool.new(max_workers: options[:workers] || 8)
      @coordinator = Statuses::Services::DaemonLifecycleCoordinator.new(
        event_queue: @event_queue,
        worker_pool: @worker_pool
      )
      @host_states = {}
      @service_states = {}
      @host_histories = {}
      @service_histories = {}
      @comments = []
      @downtimes = []
      @reload_requested = false
      @mutex = Mutex.new

      @check_executor = Engines::CheckExecutor.new(
        config_catalog: nil,
        worker_pool: @worker_pool,
        host_states: @host_states,
        service_states: @service_states,
        host_histories: @host_histories,
        service_histories: @service_histories,
        mutex: @mutex,
        log_file_path: log_file_path
      )

      @command_applier = Engines::ExternalCommandApplier.new(
        config_catalog: nil,
        event_queue: @event_queue,
        host_states: @host_states,
        service_states: @service_states,
        comments: @comments,
        downtimes: @downtimes,
        mutex: @mutex,
        notifications_enabled: 1
      )
    end

    def run!
      puts "\n" + ('=' * 72)
      puts "  🚀 NAGIOS CORE - PURE-RUBY STANDALONE MONITORING ENGINE"
      puts "  Ruby Version   : #{RUBY_VERSION} (Engine: #{RUBY_ENGINE})"
      puts "  PID            : #{Process.pid}"
      puts "  Config File    : #{@options[:config_file] || 'Built-in Demo Configuration'}"
      puts "  Status File    : #{status_file_path}"
      puts "  Command Pipe   : #{command_pipe_path}"
      puts "  Log File       : #{log_file_path}"
      puts "  PID File       : #{pid_file_path}"
      puts ('=' * 72) + "\n"

      load_configuration!
      return if @options[:verify_only]

      FileUtils.mkdir_p(File.dirname(pid_file_path))
      File.write(pid_file_path, Process.pid.to_s)

      Statuses::Services::DaemonLogger.append_log(
        Statuses::Services::DaemonLogger.format_entry("Nagios Core 4.5.14-PureRuby starting... (PID=#{Process.pid})"),
        log_file_path
      )
      Statuses::Services::DaemonLogger.append_log(
        Statuses::Services::DaemonLogger.format_entry("LOG VERSION: 2.0"),
        log_file_path
      )

      setup_signal_traps!
      setup_command_pipe!
      schedule_initial_checks!

      @running = true
      @coordinator.start!
      puts "✅ [Daemon] Engine initialized and running. Listening for events...\n\n"

      main_monitoring_loop
    end

    def status_file_path
      @options[:status_file] || File.expand_path('../../tmp/status.dat', __dir__)
    end

    def log_file_path
      @options[:log_file] || ENV['NAGIOS_LOG_FILE'] || File.join(File.dirname(status_file_path), 'nagios.log')
    end

    def pid_file_path
      @options[:pid_file] || ENV['NAGIOS_PID_FILE'] || File.join(File.dirname(status_file_path), 'nagios.pid')
    end

    def command_pipe_path
      @options[:command_pipe] || File.expand_path('../../tmp/nagios.cmd', __dir__)
    end

    def reload_configuration!
      load_configuration!
      @event_queue.clear!
      schedule_initial_checks!
      dump_runtime_status!
      msg = "Configuration reloaded successfully (Registered: #{@config_catalog.hosts.size} hosts, #{@config_catalog.services.size} services)"
      Statuses::Services::DaemonLogger.append_log(Statuses::Services::DaemonLogger.format_entry(msg), log_file_path)
      puts "✅ [Daemon] #{msg}\n\n"
    rescue => e
      puts "❌ [Daemon] Configuration reload error: #{e.message}\n"
    end

    def dump_runtime_status!
      Engines::StatusDumper.dump!(
        target_file: status_file_path,
        start_time: @coordinator.status.start_time,
        active_workers: @worker_pool.stats[:active_workers],
        host_states: @host_states,
        service_states: @service_states,
        comments: @comments,
        downtimes: @downtimes,
        notifications_enabled: @command_applier.notifications_enabled,
        mutex: @mutex
      )
    end

    private

    def setup_command_pipe!
      fifo_path = command_pipe_path
      FileUtils.mkdir_p(File.dirname(fifo_path))
      File.mkfifo(fifo_path) rescue nil unless File.exist?(fifo_path)
      if File.exist?(fifo_path) && File.pipe?(fifo_path)
        @command_pipe_io = File.open(fifo_path, File::RDWR | File::NONBLOCK) rescue nil
      end
    end

    def load_configuration!
      puts "📦 [Config] Parsing object configurations..."
      cfg_file = @options[:config_file]
      content = cfg_file && File.exist?(cfg_file) ? File.read(cfg_file) : default_sample_cfg
      @config_catalog = Statuses::Services::ObjectConfigParser.parse(content)

      @check_executor.update_catalog!(@config_catalog)
      @command_applier.update_catalog!(@config_catalog)

      puts "    ✓ Registered Hosts    : #{@config_catalog.hosts.size}"
      puts "    ✓ Registered Services : #{@config_catalog.services.size}"
      puts "    ✓ Registered Commands : #{@config_catalog.commands.size}"
      puts "\n✅ [Verification] Configuration syntax OK! No errors detected.\n" if @options[:verify_only]
    end

    def schedule_initial_checks!
      now = Time.now.to_i

      @config_catalog.hosts.each do |host_name, host_data|
        interval = (host_data['check_interval'] || 30).to_i
        cmd = host_data['check_command'] || "ping -c 1 #{host_data['address'] || '127.0.0.1'}"
        @event_queue.schedule(
          type: :host_check,
          run_time: now,
          interval: interval,
          target: host_name,
          payload: { command: cmd, host_data: host_data }
        )
      end

      items = @config_catalog.services
      step = items.size > 0 ? (15.0 / items.size) : 1.0
      items.each_with_index do |svc_data, idx|
        host_name = svc_data['host_name']
        svc_desc = svc_data['service_description']
        @event_queue.schedule(
          type: :service_check,
          run_time: (now + (idx * step)).to_i,
          interval: (svc_data['check_interval'] || 30).to_i,
          target: "#{host_name}/#{svc_desc}",
          payload: { host_name: host_name, service_description: svc_desc, command: svc_data['check_command'] || 'true', svc_data: svc_data }
        )
      end
      puts "📅 [Scheduler] Queued #{@event_queue.size} checks into Priority Queue."
    end

    def main_monitoring_loop
      last_flush = Time.now.to_i

      while @running
        now = Time.now.to_i

        if @reload_requested
          @reload_requested = false
          puts "\n🔄 [Daemon] Processing SIGHUP reload request..."
          reload_configuration!
        end

        @event_queue.process_due(now).each do |event|
          @check_executor.execute_event(event)
        end

        process_external_commands!

        if now - last_flush >= 10
          dump_runtime_status!
          last_flush = now
        end

        sleep 0.5
      end

      shutdown!
    end

    def process_external_commands!
      return unless @command_pipe_io

      begin
        lines = @command_pipe_io.read_nonblock(8192)
        return unless lines

        lines.each_line do |cmd|
          clean_cmd = cmd.strip
          next if clean_cmd.empty?

          puts "📥 [External Command] Processing: #{clean_cmd}"
          Statuses::Services::DaemonLogger.log_command(clean_cmd, log_path: log_file_path)
          result = Statuses::Services::ExternalCommandHandler.process(clean_cmd)
          next unless result&.success?

          reload_req, state_mod = @command_applier.apply!(result)
          if reload_req
            puts "🔄 [External Command] Processing RELOAD_CONFIG..."
            reload_configuration!
          elsif state_mod
            dump_runtime_status!
          end
        end
      rescue IO::WaitReadable, Errno::EAGAIN
        # Non-blocking empty pipe
      rescue => _e
        # Ignore transients
      end
    end

    def setup_signal_traps!
      %w[INT TERM].each do |signal|
        trap(signal) do
          puts "\n\n⚠️  Received SIG#{signal}. Gracefully stopping Ruby Engine..."
          @running = false
        end
      end

      trap('HUP') do
        @reload_requested = true
      end
    end

    def shutdown!
      @coordinator.stop!
      @command_pipe_io&.close rescue nil
      dump_runtime_status!
      File.unlink(pid_file_path) rescue nil
      Statuses::Services::DaemonLogger.append_log(
        Statuses::Services::DaemonLogger.format_entry("Nagios Core 4.5.14-PureRuby shutting down..."),
        log_file_path
      )
      puts "🛑 [Daemon] Engine stopped. Runtime status successfully saved to #{status_file_path}."
      puts "Done. 👋\n\n"
    end

    def default_sample_cfg
      "define host { host_name localhost; address 127.0.0.1; check_interval 10; max_check_attempts 3; check_command check_ping }\n" \
      "define service { host_name localhost; service_description Ping Latency; check_command ping -c 1 127.0.0.1; check_interval 10; max_check_attempts 3 }"
    end
  end
end

module NagiosRubyEngine
  StandaloneDaemon = Engines::StandaloneDaemon
end
