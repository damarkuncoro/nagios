# frozen_string_literal: true

module Statuses
  module Services
    # Adopts high-level tactical health aggregation from cgi/tac.c
    # Computes unhandled vs acknowledged problems, downtime suppression,
    # flapping counts, and health gauge percentages for hosts and services.
    class TacticalOverviewAggregator
      HostBreakdown = Struct.new(
        :total,
        :up,
        :down_unhandled,
        :down_ack,
        :down_downtime,
        :unreachable,
        :unreachable_unhandled,
        :unreachable_ack,
        :unreachable_downtime,
        :pending,
        :flapping,
        keyword_init: true
      )

      ServiceBreakdown = Struct.new(
        :total,
        :ok,
        :warning_unhandled,
        :warning_ack,
        :warning_downtime,
        :critical_unhandled,
        :critical_ack,
        :critical_downtime,
        :unknown_unhandled,
        :unknown_ack,
        :unknown_downtime,
        :pending,
        :flapping,
        keyword_init: true
      )

      TacticalSummary = Struct.new(
        :program_status,
        :host_health_pct,
        :service_health_pct,
        :cluster_health_pct,
        :total_unhandled_problems,
        :hosts,
        :services,
        keyword_init: true
      ) do
        def to_h
          {
            program_status: program_status,
            host_health_pct: host_health_pct,
            service_health_pct: service_health_pct,
            cluster_health_pct: cluster_health_pct,
            total_unhandled_problems: total_unhandled_problems,
            hosts: {
              total: hosts.total,
              up: hosts.up,
              down_unhandled: hosts.down_unhandled,
              down_ack: hosts.down_ack,
              unreachable: hosts.unreachable,
              flapping: hosts.flapping
            },
            services: {
              total: services.total,
              ok: services.ok,
              warning_unhandled: services.warning_unhandled,
              warning_ack: services.warning_ack,
              critical_unhandled: services.critical_unhandled,
              critical_ack: services.critical_ack,
              pending: services.pending,
              flapping: services.flapping
            }
          }
        end
      end

      class << self
        def aggregate(hosts:, services:, program_status: nil)
          new.aggregate(hosts: hosts, services: services, program_status: program_status)
        end
      end

      # Computes full tactical overview summary (cgi/tac.c: compute_tactical_data)
      def aggregate(hosts:, services:, program_status: nil)
        h_breakdown = aggregate_hosts(Array(hosts))
        s_breakdown = aggregate_services(Array(services))

        total_hosts = h_breakdown.total
        total_services = s_breakdown.total

        h_health = total_hosts.positive? ? ((h_breakdown.up.to_f / total_hosts) * 100).round(1) : 100.0
        s_health = total_services.positive? ? ((s_breakdown.ok.to_f / total_services) * 100).round(1) : 100.0

        total_nodes = total_hosts + total_services
        cluster_health = if total_nodes.positive?
                           (((h_breakdown.up + s_breakdown.ok).to_f / total_nodes) * 100).round(1)
                         else
                           100.0
                         end

        unhandled_total = h_breakdown.down_unhandled + h_breakdown.unreachable_unhandled +
                          s_breakdown.warning_unhandled + s_breakdown.critical_unhandled + s_breakdown.unknown_unhandled

        TacticalSummary.new(
          program_status: program_status,
          host_health_pct: h_health,
          service_health_pct: s_health,
          cluster_health_pct: cluster_health,
          total_unhandled_problems: unhandled_total,
          hosts: h_breakdown,
          services: s_breakdown
        )
      end

      private

      def aggregate_hosts(hosts)
        b = HostBreakdown.new(
          total: hosts.size,
          up: 0,
          down_unhandled: 0,
          down_ack: 0,
          down_downtime: 0,
          unreachable: 0,
          unreachable_unhandled: 0,
          unreachable_ack: 0,
          unreachable_downtime: 0,
          pending: 0,
          flapping: 0
        )

        hosts.each do |h|
          st = (get_attr(h, :status) || 'UP').to_s.upcase
          ack = is_truthy?(get_attr(h, :acknowledged) || get_attr(h, :problem_has_been_acknowledged))
          dt_depth = (get_attr(h, :scheduled_downtime_depth) || 0).to_i
          in_dt = dt_depth.positive?
          b.flapping += 1 if is_truthy?(get_attr(h, :is_flapping))

          case st
          when 'UP'
            b.up += 1
          when 'DOWN'
            if in_dt
              b.down_downtime += 1
            elsif ack
              b.down_ack += 1
            else
              b.down_unhandled += 1
            end
          when 'UNREACHABLE'
            b.unreachable += 1
            if in_dt
              b.unreachable_downtime += 1
            elsif ack
              b.unreachable_ack += 1
            else
              b.unreachable_unhandled += 1
            end
          when 'PENDING'
            b.pending += 1
          else
            b.up += 1
          end
        end

        b
      end

      def aggregate_services(services)
        b = ServiceBreakdown.new(
          total: services.size,
          ok: 0,
          warning_unhandled: 0,
          warning_ack: 0,
          warning_downtime: 0,
          critical_unhandled: 0,
          critical_ack: 0,
          critical_downtime: 0,
          unknown_unhandled: 0,
          unknown_ack: 0,
          unknown_downtime: 0,
          pending: 0,
          flapping: 0
        )

        services.each do |s|
          st = (get_attr(s, :status) || 'OK').to_s.upcase
          ack = is_truthy?(get_attr(s, :acknowledged) || get_attr(s, :problem_has_been_acknowledged))
          dt_depth = (get_attr(s, :scheduled_downtime_depth) || 0).to_i
          in_dt = dt_depth.positive?
          b.flapping += 1 if is_truthy?(get_attr(s, :is_flapping))

          case st
          when 'OK'
            b.ok += 1
          when 'WARNING'
            if in_dt
              b.warning_downtime += 1
            elsif ack
              b.warning_ack += 1
            else
              b.warning_unhandled += 1
            end
          when 'CRITICAL'
            if in_dt
              b.critical_downtime += 1
            elsif ack
              b.critical_ack += 1
            else
              b.critical_unhandled += 1
            end
          when 'UNKNOWN'
            if in_dt
              b.unknown_downtime += 1
            elsif ack
              b.unknown_ack += 1
            else
              b.unknown_unhandled += 1
            end
          when 'PENDING'
            b.pending += 1
          else
            b.ok += 1
          end
        end

        b
      end

      def get_attr(target, key)
        return nil if target.nil?

        if target.is_a?(Hash)
          target[key.to_s] || target[key.to_sym]
        elsif target.respond_to?(key)
          target.send(key)
        end
      end

      def is_truthy?(val)
        val == true || val == 1 || val.to_s.casecmp('true').zero?
      end
    end
  end
end
