module Statuses
  module UseCases
    class FetchUnhandledProblems
      def self.call(filter: nil)
        hosts = Engines::NagiosEngine.hosts.map(&:to_h)
        services = Engines::NagiosEngine.services.map(&:to_h)

        flapping_hosts = hosts.select { |h| h[:flapping] }
        flapping_services = services.select { |s| s[:flapping] }
        total_flapping = flapping_hosts.size + flapping_services.size

        if filter.to_s == 'flapping'
          unhandled_hosts = flapping_hosts
          unhandled_services = flapping_services
        else
          unhandled_hosts = hosts.select do |h|
            %w[DOWN UNREACHABLE].include?(h[:status]) && !h[:acknowledged]
          end

          unhandled_services = services.select do |s|
            %w[WARNING CRITICAL UNKNOWN].include?(s[:status]) && !s[:acknowledged]
          end
        end

        total_unhandled = unhandled_hosts.size + unhandled_services.size

        {
          hosts: unhandled_hosts,
          services: unhandled_services,
          total_unhandled: total_unhandled,
          total_flapping: total_flapping
        }
      end
    end
  end
end
