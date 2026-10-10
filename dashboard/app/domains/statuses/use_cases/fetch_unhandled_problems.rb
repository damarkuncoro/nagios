module Statuses
  module UseCases
    class FetchUnhandledProblems
      def self.call(filter: nil)
        hosts = Engines::NagiosEngine.hosts.map(&:to_h) rescue []
        services = Engines::NagiosEngine.services.map(&:to_h) rescue []

        if filter.to_s == 'flapping'
          unhandled_hosts = Services::StatusQueryEngine.filter_hosts(hosts, flapping: true).items
          unhandled_services = Services::StatusQueryEngine.filter_services(services, flapping: true).items
        else
          unhandled_hosts = Services::StatusQueryEngine.filter_hosts(hosts, unhandled_only: true).items
          unhandled_services = Services::StatusQueryEngine.filter_services(services, unhandled_only: true).items
        end

        host_totals = Services::StatusQueryEngine.calculate_host_totals(hosts)
        service_totals = Services::StatusQueryEngine.calculate_service_totals(services)

        {
          hosts: unhandled_hosts,
          services: unhandled_services,
          total_unhandled: unhandled_hosts.size + unhandled_services.size,
          total_flapping: host_totals.flapping + service_totals.flapping
        }
      end
    end
  end
end
