# frozen_string_literal: true

module Statuses
  module Services
    # Adopts SLA availability calculation and reporting from cgi/avail.c
    # Calculates uptime/downtime percentages over monitoring intervals,
    # discounting scheduled maintenance windows from SLA penalties.
    class AvailabilityCalculator
      DEFAULT_SLA_TARGET = 99.0

      HostAvailability = Struct.new(
        :name,
        :status,
        :time_up_seconds,
        :time_down_seconds,
        :time_unreachable_seconds,
        :scheduled_downtime_seconds,
        :total_seconds,
        :raw_availability_pct,
        :sla_availability_pct,
        :sla_met,
        keyword_init: true
      )

      ServiceAvailability = Struct.new(
        :host_name,
        :description,
        :status,
        :time_ok_seconds,
        :time_warning_seconds,
        :time_critical_seconds,
        :time_unknown_seconds,
        :scheduled_downtime_seconds,
        :total_seconds,
        :raw_availability_pct,
        :sla_availability_pct,
        :sla_met,
        keyword_init: true
      )

      AvailabilityReport = Struct.new(
        :window_duration_seconds,
        :host_reports,
        :service_reports,
        :overall_raw_pct,
        :overall_sla_pct,
        :overall_sla_met,
        keyword_init: true
      )

      class << self
        def calculate(hosts:, services:, window_seconds: 86400, sla_target: DEFAULT_SLA_TARGET)
          new(sla_target: sla_target).calculate(hosts: hosts, services: services, window_seconds: window_seconds)
        end
      end

      def initialize(sla_target: DEFAULT_SLA_TARGET)
        @sla_target = sla_target.to_f
      end

      # Generates comprehensive availability report (cgi/avail.c: compute_availability)
      def calculate(hosts:, services:, window_seconds: 86400)
        window = [window_seconds.to_i, 1].max

        h_reports = Array(hosts).map do |host|
          calculate_host(host, window)
        end

        s_reports = Array(services).map do |service|
          calculate_service(service, window)
        end

        total_nodes = h_reports.size + s_reports.size
        overall_sla = if total_nodes.positive?
                        ((h_reports.count(&:sla_met) + s_reports.count(&:sla_met)).to_f / total_nodes * 100).round(2)
                      else
                        100.0
                      end

        overall_raw = if total_nodes.positive?
                        ((h_reports.map(&:raw_availability_pct) + s_reports.map(&:raw_availability_pct)).sum / total_nodes).round(2)
                      else
                        100.0
                      end

        AvailabilityReport.new(
          window_duration_seconds: window,
          host_reports: h_reports,
          service_reports: s_reports,
          overall_raw_pct: overall_raw,
          overall_sla_pct: overall_sla,
          overall_sla_met: overall_sla >= @sla_target
        )
      end

      # Computes single host availability (cgi/avail.c: compute_host_availability)
      def calculate_host(host, window_seconds)
        status = get_attr(host, :status) || 'UP'
        dt_depth = get_attr(host, :scheduled_downtime_depth).to_i

        # If data provides explicit seconds, use them; otherwise infer from status & downtime depth
        dt_seconds = get_attr(host, :downtime_seconds).to_i
        dt_seconds = (status != 'UP' && dt_depth.positive?) ? window_seconds : dt_seconds

        time_up = get_attr(host, :time_up_seconds)
        time_down = get_attr(host, :time_down_seconds)
        time_unreach = get_attr(host, :time_unreachable_seconds)

        if time_up.nil? || time_down.nil?
          case status.to_s.upcase
          when 'UP'
            time_up = window_seconds
            time_down = 0
            time_unreach = 0
          when 'DOWN'
            time_up = 0
            time_down = window_seconds
            time_unreach = 0
          else # UNREACHABLE
            time_up = 0
            time_down = 0
            time_unreach = window_seconds
          end
        end

        raw_pct = (time_up.to_f / window_seconds * 100).round(2)

        # Net SLA excludes scheduled maintenance windows (cgi/avail.c: count_scheduled_downtime_as_uptime)
        net_window = [window_seconds - dt_seconds, 1].max
        sla_pct = [((time_up.to_f / net_window) * 100).round(2), 100.0].min

        HostAvailability.new(
          name: get_attr(host, :name) || get_attr(host, :host_name),
          status: status,
          time_up_seconds: time_up,
          time_down_seconds: time_down,
          time_unreachable_seconds: time_unreach,
          scheduled_downtime_seconds: dt_seconds,
          total_seconds: window_seconds,
          raw_availability_pct: raw_pct,
          sla_availability_pct: sla_pct,
          sla_met: sla_pct >= @sla_target
        )
      end

      # Computes single service availability (cgi/avail.c: compute_service_availability)
      def calculate_service(service, window_seconds)
        status = get_attr(service, :status) || 'OK'
        dt_depth = get_attr(service, :scheduled_downtime_depth).to_i

        dt_seconds = get_attr(service, :downtime_seconds).to_i
        dt_seconds = (status != 'OK' && dt_depth.positive?) ? window_seconds : dt_seconds

        time_ok = get_attr(service, :time_ok_seconds)
        time_warn = get_attr(service, :time_warning_seconds)
        time_crit = get_attr(service, :time_critical_seconds)
        time_unknown = get_attr(service, :time_unknown_seconds)

        if time_ok.nil? || time_crit.nil?
          case status.to_s.upcase
          when 'OK'
            time_ok = window_seconds
            time_warn = 0
            time_crit = 0
            time_unknown = 0
          when 'WARNING'
            time_ok = 0
            time_warn = window_seconds
            time_crit = 0
            time_unknown = 0
          when 'CRITICAL'
            time_ok = 0
            time_warn = 0
            time_crit = window_seconds
            time_unknown = 0
          else
            time_ok = 0
            time_warn = 0
            time_crit = 0
            time_unknown = window_seconds
          end
        end

        # WARNING can optionally be counted as partial uptime (e.g. 95%), OK as 100%
        effective_uptime = time_ok.to_f + (time_warn.to_f * 0.95)
        raw_pct = ((effective_uptime / window_seconds) * 100).round(2)

        net_window = [window_seconds - dt_seconds, 1].max
        sla_pct = [((effective_uptime / net_window) * 100).round(2), 100.0].min

        ServiceAvailability.new(
          host_name: get_attr(service, :host_name),
          description: get_attr(service, :description),
          status: status,
          time_ok_seconds: time_ok,
          time_warning_seconds: time_warn,
          time_critical_seconds: time_crit,
          time_unknown_seconds: time_unknown,
          scheduled_downtime_seconds: dt_seconds,
          total_seconds: window_seconds,
          raw_availability_pct: raw_pct,
          sla_availability_pct: sla_pct,
          sla_met: sla_pct >= @sla_target
        )
      end

      private

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
