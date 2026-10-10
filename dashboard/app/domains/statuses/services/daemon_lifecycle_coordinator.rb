# frozen_string_literal: true

module Statuses
  module Services
    # Adopts core daemon loop, lifecycle, and subsystem orchestration from base/nagios.c
    # Coordinates TimedEventQueue, WorkerProcessPool, StateRetention, EventRadioDispatcher, and DaemonLogger.
    class DaemonLifecycleCoordinator
      DaemonStatus = Struct.new(
        :state,
        :uptime_seconds,
        :start_time,
        :queued_events,
        :active_workers,
        :registered_neb_modules,
        :health_percentage,
        keyword_init: true
      ) do
        def running?
          state == :running
        end

        def paused?
          state == :paused
        end

        def stopped?
          state == :stopped
        end
      end

      class << self
        def instance
          @instance ||= new
        end

        def start!
          instance.start!
        end

        def stop!
          instance.stop!
        end

        def pause!
          instance.pause!
        end

        def resume!
          instance.resume!
        end

        def tick!(current_time = nil)
          instance.tick!(current_time)
        end

        def process_command(raw_command_line)
          instance.process_command(raw_command_line)
        end

        def status
          instance.status
        end
      end

      attr_reader :event_queue, :worker_pool, :neb_registry, :radio_dispatcher

      def initialize(
        event_queue: TimedEventQueue.new,
        worker_pool: WorkerProcessPool.new,
        neb_registry: NebModuleRegistry.instance,
        radio_dispatcher: EventRadioDispatcher.instance
      )
        @event_queue = event_queue
        @worker_pool = worker_pool
        @neb_registry = neb_registry
        @radio_dispatcher = radio_dispatcher
        @state = :stopped
        @start_time = nil
        @mutex = Mutex.new
      end

      # Starts the monitoring daemon subsystems (base/nagios.c: init_subsystems & main)
      def start!
        @mutex.synchronize do
          return false if @state == :running

          now = Time.respond_to?(:current) ? Time.current : Time.now
          @start_time = now
          @state = :running

          DaemonLogger.format_entry('Nagios Core Modern Ruby Engine starting...')
          @neb_registry.dispatch_event(:process_start, { timestamp: now.to_i })
          @radio_dispatcher.broadcast(:alerts, { event: 'DAEMON_STARTED', time: now.to_i })
          true
        end
      end

      # Stops the monitoring daemon and persists retention state (base/nagios.c: clean_exit)
      def stop!
        @mutex.synchronize do
          return false if @state == :stopped

          now = Time.respond_to?(:current) ? Time.current : Time.now
          @state = :stopped
          @start_time = nil

          @neb_registry.dispatch_event(:process_stop, { timestamp: now.to_i })
          @radio_dispatcher.broadcast(:alerts, { event: 'DAEMON_STOPPED', time: now.to_i })
          DaemonLogger.format_entry('Nagios Core Modern Ruby Engine stopped.')
          true
        end
      end

      def pause!
        @mutex.synchronize do
          @state = :paused if @state == :running
        end
      end

      def resume!
        @mutex.synchronize do
          @state = :running if @state == :paused
        end
      end

      # Executes single iteration loop (base/nagios.c: main_loop)
      def tick!(current_time = nil)
        return [] unless @state == :running

        # Process all due events from priority queue
        executed = @event_queue.process_due(current_time) do |event|
          if event.type.in?(%i[service_check host_check])
            @radio_dispatcher.broadcast(
              event.type == :host_check ? :host_checks : :service_checks,
              { target: event.target, time: event.run_time }
            )
          end
        end

        @neb_registry.dispatch_event(:loop_tick, { executed_count: executed.size })
        executed
      end

      # Executes external command against daemon state (base/commands.c)
      def process_command(raw_command_line)
        ExternalCommandHandler.process(raw_command_line)
      end

      # Reports daemon health and subsystem metrics
      def status
        @mutex.synchronize do
          now = Time.respond_to?(:current) ? Time.current : Time.now
          uptime = @start_time ? (now - @start_time).to_i : 0

          DaemonStatus.new(
            state: @state,
            uptime_seconds: uptime,
            start_time: @start_time,
            queued_events: @event_queue.size,
            active_workers: @worker_pool.stats[:active_workers],
            registered_neb_modules: @neb_registry.modules.size,
            health_percentage: @state == :running ? 100.0 : 0.0
          )
        end
      end
    end
  end
end
