# frozen_string_literal: true

module Statuses
  module UseCases
    class FetchUnhandledProblems
      def self.call(filter: nil)
        hosts = begin
          Engines::NagiosEngine.hosts.map(&:to_h)
        rescue StandardError
          []
        end

        services = begin
          Engines::NagiosEngine.services.map(&:to_h)
        rescue StandardError
          []
        end

        f = filter.to_s.strip.downcase

        case f
        when 'flapping'
          unhandled_hosts = Services::StatusQueryEngine.filter_hosts(hosts, flapping: true).items
          unhandled_services = Services::StatusQueryEngine.filter_services(services, flapping: true).items
        when 'hard'
          unhandled_hosts = Services::StatusQueryEngine.filter_hosts(hosts, unhandled_only: true, state_type: 'HARD').items
          unhandled_services = Services::StatusQueryEngine.filter_services(services, unhandled_only: true, state_type: 'HARD').items
        when 'critical'
          unhandled_hosts = Services::StatusQueryEngine.filter_hosts(hosts, unhandled_only: true, state: 'DOWN').items
          unhandled_services = Services::StatusQueryEngine.filter_services(services, unhandled_only: true, state: 'CRITICAL').items
        else
          unhandled_hosts = Services::StatusQueryEngine.filter_hosts(hosts, unhandled_only: true).items
          unhandled_services = Services::StatusQueryEngine.filter_services(services, unhandled_only: true).items
        end

        host_totals = Services::StatusQueryEngine.calculate_host_totals(hosts)
        service_totals = Services::StatusQueryEngine.calculate_service_totals(services)

        all_unhandled_hosts = Services::StatusQueryEngine.filter_hosts(hosts, unhandled_only: true).items
        all_unhandled_services = Services::StatusQueryEngine.filter_services(services, unhandled_only: true).items

        hard_hosts = Services::StatusQueryEngine.filter_hosts(hosts, unhandled_only: true, state_type: 'HARD').items
        hard_services = Services::StatusQueryEngine.filter_services(services, unhandled_only: true, state_type: 'HARD').items

        crit_hosts = Services::StatusQueryEngine.filter_hosts(hosts, unhandled_only: true, state: 'DOWN').items
        crit_services = Services::StatusQueryEngine.filter_services(services, unhandled_only: true, state: 'CRITICAL').items

        {
          hosts: unhandled_hosts,
          services: unhandled_services,
          total_unhandled: all_unhandled_hosts.size + all_unhandled_services.size,
          total_flapping: host_totals.flapping + service_totals.flapping,
          total_hard: hard_hosts.size + hard_services.size,
          total_critical: crit_hosts.size + crit_services.size
        }
      end
    end
  end
end
