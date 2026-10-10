# frozen_string_literal: true

require 'date'
require 'time'

module Statuses
  module Services
    # Adopts historical state trends analysis from cgi/trends.c
    # Computes cumulative time-in-state (OK, WARNING, CRITICAL, UNKNOWN, UP, DOWN),
    # percentage availability, downtime windows, transition counts, and Mean Time To Recovery (MTTR).
    class TrendsCalculator
      StateBreakdown = Struct.new(
        :monitored_seconds,
        :time_ok,
        :time_warning,
        :time_critical,
        :time_unknown,
        :time_downtime,
        :time_indeterminate,
        :percent_ok,
        :percent_warning,
        :percent_critical,
        :percent_unknown,
        :percent_downtime,
        :availability_pct,
        :total_transitions,
        :mean_time_to_recovery,
        keyword_init: true
      )

      DailyBucket = Struct.new(
        :date_str,
        :date,
        :ok_count,
        :warning_count,
        :critical_count,
        :unknown_count,
        :total_alerts,
        :health_ratio,
        keyword_init: true
      )

      class << self
        def calculate_time_in_state(transitions:, start_time:, end_time:, type: :service, initial_state: nil)
          new.calculate_time_in_state(
            transitions: transitions,
            start_time: start_time,
            end_time: end_time,
            type: type,
            initial_state: initial_state
          )
        end

        def aggregate_daily(alerts:, days: 7, now: Time.now)
          new.aggregate_daily(alerts: alerts, days: days, now: now)
        end
      end

      # Computes duration-in-state between start_time and end_time (cgi/trends.c: graph_trend_data)
      def calculate_time_in_state(transitions:, start_time:, end_time:, type: :service, initial_state: nil)
        t_start = to_epoch(start_time)
        t_end = to_epoch(end_time)
        total_seconds = [t_end - t_start, 0].max

        return empty_breakdown(total_seconds) if total_seconds.zero?

        default_ok_state = type == :host ? 'UP' : 'OK'
        current_state = initial_state ? initial_state.to_s.upcase : default_ok_state
        current_in_dt = false

        time_ok = 0
        time_warn = 0
        time_crit = 0
        time_unk = 0
        time_dt = 0

        # Sort transitions chronologically
        sorted_events = transitions.map do |e|
          {
            time: to_epoch(get_attr(e, :timestamp) || get_attr(e, :time)),
            state: normalize_state(get_attr(e, :state) || get_attr(e, :status)),
            in_downtime: is_truthy?(get_attr(e, :in_downtime) || get_attr(e, :scheduled_downtime))
          }
        end.sort_by { |e| e[:time] }

        cursor = t_start
        recovery_intervals = []
        problem_start_time = nil
        transition_count = 0

        sorted_events.each do |event|
          ev_time = event[:time]
          next if ev_time < t_start # Handled by initial assumed state
          break if cursor >= t_end

          slice_end = [ev_time, t_end].min
          slice_duration = [slice_end - cursor, 0].max

          if slice_duration.positive?
            if current_in_dt
              time_dt += slice_duration
            else
              case current_state
              when 'OK', 'UP'
                time_ok += slice_duration
              when 'WARNING'
                time_warn += slice_duration
              when 'CRITICAL', 'DOWN'
                time_crit += slice_duration
              else
                time_unk += slice_duration
              end
            end
          end

          # Check recovery transition
          new_state = event[:state]
          if %w[CRITICAL DOWN WARNING].include?(current_state) && %w[OK UP].include?(new_state)
            if problem_start_time
              recovery_intervals << (ev_time - problem_start_time)
              problem_start_time = nil
            end
          elsif %w[CRITICAL DOWN WARNING].include?(new_state) && %w[OK UP].include?(current_state)
            problem_start_time = ev_time
          end

          transition_count += 1 if current_state != new_state
          current_state = new_state
          current_in_dt = event[:in_downtime]
          cursor = slice_end
        end

        # Tail end from last transition to t_end
        if cursor < t_end
          tail_duration = t_end - cursor
          if current_in_dt
            time_dt += tail_duration
          else
            case current_state
            when 'OK', 'UP'
              time_ok += tail_duration
            when 'WARNING'
              time_warn += tail_duration
            when 'CRITICAL', 'DOWN'
              time_crit += tail_duration
            else
              time_unk += tail_duration
            end
          end
        end

        pct_ok = ((time_ok.to_f / total_seconds) * 100).round(2)
        pct_warn = ((time_warn.to_f / total_seconds) * 100).round(2)
        pct_crit = ((time_crit.to_f / total_seconds) * 100).round(2)
        pct_unk = ((time_unk.to_f / total_seconds) * 100).round(2)
        pct_dt = ((time_dt.to_f / total_seconds) * 100).round(2)

        # Availability % (uptime / non-downtime time)
        effective_time = [total_seconds - time_dt, 1].max
        avail_pct = [((time_ok.to_f / effective_time) * 100).round(2), 100.0].min

        mttr = recovery_intervals.any? ? (recovery_intervals.sum.to_f / recovery_intervals.size).round(1) : 0.0

        StateBreakdown.new(
          monitored_seconds: total_seconds,
          time_ok: time_ok,
          time_warning: time_warn,
          time_critical: time_crit,
          time_unknown: time_unk,
          time_downtime: time_dt,
          time_indeterminate: 0,
          percent_ok: pct_ok,
          percent_warning: pct_warn,
          percent_critical: pct_crit,
          percent_unknown: pct_unk,
          percent_downtime: pct_dt,
          availability_pct: avail_pct,
          total_transitions: transition_count,
          mean_time_to_recovery: mttr
        )
      end

      # Generates daily stacked trend statistics for the given days window
      def aggregate_daily(alerts:, days: 7, now: Time.now)
        base_date = now.to_date
        alerts_list = Array(alerts)

        (0...days).map do |i|
          date = base_date - i
          date_str = date.strftime('%d %b')

          day_alerts = alerts_list.select do |a|
            ts = get_attr(a, :timestamp) || get_attr(a, :time)
            ts && to_time(ts).to_date == date
          end

          ok_count = day_alerts.count { |a| %w[OK UP RECOVERY].include?(normalize_state(get_attr(a, :state) || get_attr(a, :status))) }
          warn_count = day_alerts.count { |a| normalize_state(get_attr(a, :state) || get_attr(a, :status)) == 'WARNING' }
          crit_count = day_alerts.count { |a| %w[CRITICAL DOWN UNREACHABLE].include?(normalize_state(get_attr(a, :state) || get_attr(a, :status))) }
          unk_count = day_alerts.count { |a| normalize_state(get_attr(a, :state) || get_attr(a, :status)) == 'UNKNOWN' }
          total = day_alerts.size

          health_ratio = total.positive? ? (((ok_count + 1).to_f / (total + 1)) * 100).round(1) : 100.0

          DailyBucket.new(
            date_str: date_str,
            date: date,
            ok_count: ok_count,
            warning_count: warn_count,
            critical_count: crit_count,
            unknown_count: unk_count,
            total_alerts: total,
            health_ratio: health_ratio
          )
        end.reverse
      end

      private

      def empty_breakdown(seconds)
        StateBreakdown.new(
          monitored_seconds: seconds,
          time_ok: 0,
          time_warning: 0,
          time_critical: 0,
          time_unknown: 0,
          time_downtime: 0,
          time_indeterminate: 0,
          percent_ok: 100.0,
          percent_warning: 0.0,
          percent_critical: 0.0,
          percent_unknown: 0.0,
          percent_downtime: 0.0,
          availability_pct: 100.0,
          total_transitions: 0,
          mean_time_to_recovery: 0.0
        )
      end

      def normalize_state(st)
        case st.to_s.upcase
        when 'UP', 'RECOVERY', 'OK' then 'OK'
        when 'WARN', 'WARNING' then 'WARNING'
        when 'CRIT', 'CRITICAL', 'DOWN' then 'CRITICAL'
        when 'UNREACHABLE' then 'CRITICAL'
        when 'UNKNOWN' then 'UNKNOWN'
        else 'UNKNOWN'
        end
      end

      def to_epoch(val)
        return 0 if val.nil?

        case val
        when Time then val.to_i
        when DateTime then val.to_time.to_i
        when Date then val.to_time.to_i
        when Numeric then val.to_i
        when String
          begin
            Time.parse(val).to_i
          rescue StandardError
            val.to_i
          end
        else val.to_i
        end
      end

      def to_time(val)
        case val
        when Time then val
        when Date, DateTime then val.to_time
        when Numeric then Time.at(val.to_i)
        when String
          begin
            Time.parse(val)
          rescue StandardError
            Time.at(val.to_i)
          end
        else Time.now
        end
      end

      def is_truthy?(val)
        val == true || val == 1 || val.to_s.casecmp('true').zero?
      end

      def get_attr(target, key)
        return nil if target.nil?

        if target.is_a?(Hash)
          target[key.to_s] || target[key.to_sym]
        elsif target.respond_to?(key)
          target.send(key)
        end
      end
    end
  end
end
