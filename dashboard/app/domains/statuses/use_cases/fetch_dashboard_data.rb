module Statuses
  module UseCases
    class FetchDashboardData
      def self.call
        hosts = Engines::NagiosEngine.hosts.map(&:to_h)
        services = Engines::NagiosEngine.services.map(&:to_h)
        program_status = Engines::NagiosEngine.program_status

        host_stats = {
          total: hosts.size,
          up: hosts.count { |h| h[:status] == 'UP' },
          down: hosts.count { |h| h[:status] == 'DOWN' },
          unreachable: hosts.count { |h| h[:status] == 'UNREACHABLE' }
        }

        service_stats = {
          total: services.size,
          ok: services.count { |s| s[:status] == 'OK' },
          warning: services.count { |s| s[:status] == 'WARNING' },
          critical: services.count { |s| s[:status] == 'CRITICAL' },
          pending: services.count { |s| s[:status] == 'PENDING' }
        }

        {
          hosts: hosts,
          services: services,
          program_status: program_status,
          host_stats: host_stats,
          service_stats: service_stats
        }
      end
    end
  end
end
