# frozen_string_literal: true

module Statuses
  module Services
    # Adopts timed event priority queue and loop from base/events.c
    # Implements high-resolution event scheduling, interleave spacing, and execution dispatching.
    class TimedEventQueue
      EVENT_TYPES = {
        service_check: 0,
        host_check: 1,
        retention_save: 2,
        status_save: 3,
        scheduled_downtime: 4,
        notification: 5,
        log_rotation: 6,
        custom: 99
      }.freeze

      TimedEvent = Struct.new(
        :id,
        :type,
        :run_time,
        :interval,
        :target,
        :payload,
        :callback,
        keyword_init: true
      ) do
        def due?(current_time = nil)
          now_ts = current_time ? current_time.to_i : (Time.respond_to?(:current) ? Time.current : Time.now).to_i
          run_time.to_i <= now_ts
        end

        def recurring?
          interval.to_i.positive?
        end
      end

      def initialize
        @events = []
        @mutex = Mutex.new
        @next_id = 1
      end

      # Schedules a new timed event into priority queue
      def schedule(type:, run_time:, interval: 0, target: nil, payload: {}, &callback)
        @mutex.synchronize do
          event = TimedEvent.new(
            id: @next_id,
            type: type.to_sym,
            run_time: run_time.is_a?(Time) ? run_time.to_i : run_time.to_i,
            interval: interval.to_i,
            target: target,
            payload: payload,
            callback: callback
          )
          @next_id += 1
          insert_sorted(event)
          event
        end
      end

      # Interleaves checks evenly across interval window (base/events.c init_timing_loop)
      # Prevents spikes by spreading initial run times evenly
      def schedule_interleaved(items, type:, interval_seconds:, start_time: nil, &block)
        return [] if items.empty?

        base_time = start_time ? start_time.to_i : (Time.respond_to?(:current) ? Time.current : Time.now).to_i
        step = interval_seconds.to_f / items.size
        scheduled = []

        items.each_with_index do |item, idx|
          run_time = (base_time + (idx * step)).to_i
          event = schedule(
            type: type,
            run_time: run_time,
            interval: interval_seconds,
            target: item,
            &block
          )
          scheduled << event
        end

        scheduled
      end

      # Retrieves all events whose run_time <= current_time without removing them
      def peek_due(current_time = nil)
        now_ts = current_time ? current_time.to_i : (Time.respond_to?(:current) ? Time.current : Time.now).to_i
        @mutex.synchronize do
          @events.select { |e| e.run_time <= now_ts }
        end
      end

      # Pops and executes all due events, automatically rescheduling recurring events
      def process_due(current_time = nil, &custom_executor)
        now_ts = current_time ? current_time.to_i : (Time.respond_to?(:current) ? Time.current : Time.now).to_i
        due = []

        @mutex.synchronize do
          partition_idx = @events.find_index { |e| e.run_time > now_ts } || @events.size
          due = @events.slice!(0, partition_idx)

          # Reschedule recurring events
          due.each do |event|
            if event.recurring?
              next_event = TimedEvent.new(
                id: event.id,
                type: event.type,
                run_time: event.run_time + event.interval,
                interval: event.interval,
                target: event.target,
                payload: event.payload,
                callback: event.callback
              )
              insert_sorted(next_event)
            end
          end
        end

        # Execute callbacks outside mutex lock
        executed = []
        due.each do |event|
          if custom_executor
            custom_executor.call(event)
          elsif event.callback
            event.callback.call(event)
          end
          executed << event
        end

        executed
      end

      # Cancels an event by id
      def cancel(event_id)
        @mutex.synchronize do
          @events.reject! { |e| e.id == event_id }
        end
      end

      # Returns event statistics summary (base/events.c dump_event_stats lines 43-60)
      def stats
        @mutex.synchronize do
          counts = Hash.new(0)
          @events.each { |e| counts[e.type] += 1 }
          {
            total_queued: @events.size,
            next_run_time: @events.first&.run_time,
            event_counts: counts
          }
        end
      end

      def clear!
        @mutex.synchronize do
          @events.clear
        end
      end

      def size
        @mutex.synchronize { @events.size }
      end

      private

      # Binary or linear insertion maintaining sorted ascending order by run_time
      def insert_sorted(event)
        idx = @events.bsearch_index { |e| e.run_time >= event.run_time } || @events.size
        @events.insert(idx, event)
      end
    end
  end
end
