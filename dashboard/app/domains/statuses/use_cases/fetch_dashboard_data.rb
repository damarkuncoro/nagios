# frozen_string_literal: true

module Statuses
  module UseCases
    class FetchDashboardData
      def self.call(search: nil, status: nil, sort_by: nil, sort_order: :asc)
        raw_hosts = begin
          Engines::NagiosEngine.hosts.map(&:to_h)
        rescue StandardError
          []
        end

        raw_services = begin
          Engines::NagiosEngine.services.map(&:to_h)
        rescue StandardError
          []
        end

        program_status = begin
          Engines::NagiosEngine.program_status
        rescue StandardError
          {}
        end

        host_totals = Services::StatusQueryEngine.calculate_host_totals(raw_hosts)
        service_totals = Services::StatusQueryEngine.calculate_service_totals(raw_services)

        host_stats = {
          total: host_totals.total,
          up: host_totals.up,
          down: host_totals.down,
          unreachable: host_totals.unreachable
        }

        service_stats = {
          total: service_totals.total,
          ok: service_totals.ok,
          warning: service_totals.warning,
          critical: service_totals.critical,
          pending: service_totals.pending
        }

        has_filter = !search.to_s.strip.empty? || !status.to_s.strip.empty? || !sort_by.to_s.strip.empty?

        hosts = if has_filter
          opts = {}
          opts[:keyword] = search if !search.to_s.strip.empty?
          opts[:state] = status.to_s.upcase if !status.to_s.strip.empty?
          opts[:sort_by] = sort_by if !sort_by.to_s.strip.empty?
          opts[:sort_order] = sort_order
          Services::StatusQueryEngine.filter_hosts(raw_hosts, opts).items
        else
          raw_hosts
        end

        {
          hosts: hosts,
          services: raw_services,
          program_status: program_status,
          host_stats: host_stats,
          service_stats: service_stats,
          host_totals: host_totals,
          service_totals: service_totals
        }
      end
    end
  end
end
