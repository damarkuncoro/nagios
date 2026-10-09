module Statuses
  module UseCases
    class FetchUnhandledProblems
      def self.call
        hosts = Engines::NagiosEngine.hosts.map(&:to_h)
        services = Engines::NagiosEngine.services.map(&:to_h)

        unhandled_hosts = hosts.select do |h|
          %w[DOWN UNREACHABLE].include?(h[:status]) && !h[:acknowledged]
        end

        unhandled_services = services.select do |s|
          %w[WARNING CRITICAL UNKNOWN].include?(s[:status]) && !s[:acknowledged]
        end

        total_unhandled = unhandled_hosts.size + unhandled_services.size

        {
          hosts: unhandled_hosts,
          services: unhandled_services,
          total_unhandled: total_unhandled
        }
      end
    end
  end
end
