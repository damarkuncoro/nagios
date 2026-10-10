# frozen_string_literal: true

module Statuses
  module Services
    # Adopts downtime management and lifecycle from common/downtime.c
    # Manages fixed vs flexible maintenance windows, triggered downtime cascades,
    # downtime depth tracking, and expiration evaluation.
    class DowntimeCoordinator
      ScheduledDowntime = Struct.new(
        :id,
        :type,
        :host_name,
        :service_desc,
        :entry_time,
        :start_time,
        :end_time,
        :fixed,
        :triggered_by,
        :duration,
        :author,
        :comment,
        :is_in_effect,
        :actual_start_time,
        :actual_end_time,
        keyword_init: true
      ) do
        def fixed?
          fixed == true
        end

        def flexible?
          !fixed?
        end

        def active?
          is_in_effect == true
        end

        def host_downtime?
          type == :host
        end

        def service_downtime?
          type == :service
        end
      end

      class << self
        def instance
          @instance ||= new
        end

        def schedule_host_downtime(**args)
          instance.schedule_host_downtime(**args)
        end

        def schedule_service_downtime(**args)
          instance.schedule_service_downtime(**args)
        end

        def cancel_downtime(downtime_id)
          instance.cancel_downtime(downtime_id)
        end

        def check_pending_flexible_downtime(host_name, service_desc: nil, current_state: 'CRITICAL', current_time: nil)
          instance.check_pending_flexible_downtime(host_name, service_desc: service_desc, current_state: current_state, current_time: current_time)
        end

        def check_for_expired_downtimes(current_time = nil)
          instance.check_for_expired_downtimes(current_time)
        end

        def in_downtime?(host_name, service_desc = nil)
          instance.in_downtime?(host_name, service_desc)
        end

        def downtime_depth(host_name, service_desc = nil)
          instance.downtime_depth(host_name, service_desc)
        end

        def all_downtimes
          instance.all_downtimes
        end

        def clear!
          instance.clear!
        end
      end

      attr_reader :downtimes

      def initialize(broker: Statuses::Events::Broker, logger: DaemonLogger)
        @broker = broker
        @logger = logger
        @downtimes = {}
        @next_id = 1000
        @mutex = Mutex.new
      end

      # Schedules host downtime (common/downtime.c: schedule_downtime)
      def schedule_host_downtime(
        host_name:,
        start_time:,
        end_time:,
        fixed: true,
        triggered_by: 0,
        duration: 3600,
        author: 'nagiosadmin',
        comment: 'Scheduled Maintenance',
        current_time: nil
      )
        schedule_entry(
          type: :host,
          host_name: host_name,
          service_desc: nil,
          start_time: start_time,
          end_time: end_time,
          fixed: fixed,
          triggered_by: triggered_by,
          duration: duration,
          author: author,
          comment: comment,
          current_time: current_time
        )
      end

      # Schedules service downtime (common/downtime.c: schedule_downtime)
      def schedule_service_downtime(
        host_name:,
        service_desc:,
        start_time:,
        end_time:,
        fixed: true,
        triggered_by: 0,
        duration: 3600,
        author: 'nagiosadmin',
        comment: 'Scheduled Maintenance',
        current_time: nil
      )
        schedule_entry(
          type: :service,
          host_name: host_name,
          service_desc: service_desc,
          start_time: start_time,
          end_time: end_time,
          fixed: fixed,
          triggered_by: triggered_by,
          duration: duration,
          author: author,
          comment: comment,
          current_time: current_time
        )
      end

      # Cancels scheduled downtime (common/downtime.c: delete_downtime)
      def cancel_downtime(downtime_id)
        id = downtime_id.to_i
        @mutex.synchronize do
          dt = @downtimes.delete(id)
          return false unless dt

          if dt.active?
            emit_event(:downtime_stop, dt)
            @logger.format_entry("DOWNTIME CANCELLED: ID ##{id} on #{dt.host_name}#{dt.service_desc ? '/' + dt.service_desc : ''}")
          end
          true
        end
      end

      # Evaluates flexible downtime when object changes to problem state
      # (common/downtime.c: check_pending_flex_service_downtime & check_pending_flex_host_downtime)
      def check_pending_flexible_downtime(host_name, service_desc: nil, current_state: 'CRITICAL', current_time: nil)
        now = (current_time || current_timestamp).to_i
        activated = []

        is_problem = !%w[OK UP].include?(current_state.to_s.upcase)
        return activated unless is_problem

        @mutex.synchronize do
          @downtimes.values.each do |dt|
            next if dt.fixed? || dt.active?
            next unless dt.host_name == host_name
            next if dt.service_downtime? && dt.service_desc != service_desc
            next if dt.host_downtime? && service_desc

            # Window check: now must be between start_time and end_time
            if now >= dt.start_time && now <= dt.end_time
              dt.is_in_effect = true
              dt.actual_start_time = now
              dt.actual_end_time = [now + dt.duration, dt.end_time].min

              activated << dt
              emit_event(:downtime_start, dt)
              @logger.format_entry("FLEXIBLE DOWNTIME STARTED: ID ##{dt.id} on #{dt.host_name}#{dt.service_desc ? '/' + dt.service_desc : ''}")

              # Cascade triggered downtimes
              cascade_triggered_downtimes(dt.id, now)
            end
          end
        end

        activated
      end

      # Checks and expires due active downtimes (common/downtime.c: check_for_expired_downtime)
      def check_for_expired_downtimes(current_time = nil)
        now = (current_time || current_timestamp).to_i
        expired = []

        @mutex.synchronize do
          @downtimes.each do |id, dt|
            next unless dt.active?

            limit = dt.fixed? ? dt.end_time : (dt.actual_end_time || dt.end_time)
            if now >= limit
              dt.is_in_effect = false
              expired << dt
              emit_event(:downtime_stop, dt)
              @logger.format_entry("DOWNTIME EXPIRED: ID ##{id} on #{dt.host_name}#{dt.service_desc ? '/' + dt.service_desc : ''}")
            end
          end
        end

        expired
      end

      # Calculates downtime depth for target (common/downtime.c)
      def downtime_depth(host_name, service_desc = nil)
        @mutex.synchronize do
          @downtimes.values.count do |dt|
            dt.active? && dt.host_name == host_name && (service_desc.nil? ? dt.host_downtime? : dt.service_desc == service_desc)
          end
        end
      end

      def in_downtime?(host_name, service_desc = nil)
        downtime_depth(host_name, service_desc).positive?
      end

      def all_downtimes
        @mutex.synchronize { @downtimes.values }
      end

      def clear!
        @mutex.synchronize { @downtimes.clear }
      end

      private

      def schedule_entry(**params)
        @mutex.synchronize do
          id = @next_id
          @next_id += 1

          now = (params[:current_time] || current_timestamp).to_i
          start_t = params[:start_time].to_i
          end_t = params[:end_time].to_i
          fixed = params[:fixed] == true
          triggered_by_id = params[:triggered_by].to_i
          parent_dt = triggered_by_id.positive? ? @downtimes[triggered_by_id] : nil

          if parent_dt && parent_dt.active?
            is_active = true
            actual_start = now
            actual_end = now + params[:duration].to_i
          else
            is_active = fixed && (now >= start_t && now <= end_t)
            actual_start = is_active ? start_t : nil
            actual_end = is_active ? end_t : nil
          end

          dt = ScheduledDowntime.new(
            id: id,
            type: params[:type],
            host_name: params[:host_name],
            service_desc: params[:service_desc],
            entry_time: now,
            start_time: start_t,
            end_time: end_t,
            fixed: fixed,
            triggered_by: triggered_by_id,
            duration: params[:duration].to_i,
            author: params[:author].to_s,
            comment: params[:comment].to_s,
            is_in_effect: is_active,
            actual_start_time: actual_start,
            actual_end_time: actual_end
          )

          @downtimes[id] = dt

          if is_active
            emit_event(:downtime_start, dt)
            cascade_triggered_downtimes(id, now)
          end

          @logger.format_entry("SCHEDULED DOWNTIME: ID ##{id} added for #{dt.host_name}#{dt.service_desc ? '/' + dt.service_desc : ''}")
          dt
        end
      end

      def cascade_triggered_downtimes(parent_id, current_time)
        @downtimes.values.each do |dt|
          if dt.triggered_by == parent_id && !dt.active?
            dt.is_in_effect = true
            dt.actual_start_time = current_time
            dt.actual_end_time = current_time + dt.duration
            emit_event(:downtime_start, dt)
            @logger.format_entry("TRIGGERED DOWNTIME STARTED: ID ##{dt.id} triggered by ##{parent_id}")
          end
        end
      end

      def emit_event(event_type, downtime)
        return unless @broker.respond_to?(:publish)

        @broker.publish(
          event_type,
          {
            downtime_id: downtime.id,
            host_name: downtime.host_name,
            service_desc: downtime.service_desc,
            type: downtime.type,
            fixed: downtime.fixed?
          },
          source: 'downtime_coordinator'
        )
      rescue StandardError
        # Non-fatal event publishing
      end

      def current_timestamp
        (Time.respond_to?(:current) ? Time.current : Time.now).to_i
      end
    end
  end
end
