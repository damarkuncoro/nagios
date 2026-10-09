module Statuses
  module UseCases
    class FetchTacticalOverview
      def self.call
        hosts = Engines::NagiosEngine.hosts.map(&:to_h)
        services = Engines::NagiosEngine.services.map(&:to_h)
        program_status = Engines::NagiosEngine.program_status

        total_hosts = hosts.size
        hosts_up = hosts.count { |h| h[:status] == 'UP' }
        hosts_down_unhandled = hosts.count { |h| h[:status] == 'DOWN' && !h[:acknowledged] }
        hosts_down_ack = hosts.count { |h| h[:status] == 'DOWN' && h[:acknowledged] }
        hosts_unreachable = hosts.count { |h| h[:status] == 'UNREACHABLE' }

        host_health_pct = total_hosts > 0 ? ((hosts_up.to_f / total_hosts) * 100).round(1) : 100.0

        total_services = services.size
        services_ok = services.count { |s| s[:status] == 'OK' }
        services_warning_unhandled = services.count { |s| s[:status] == 'WARNING' && !s[:acknowledged] }
        services_warning_ack = services.count { |s| s[:status] == 'WARNING' && s[:acknowledged] }
        services_critical_unhandled = services.count { |s| s[:status] == 'CRITICAL' && !s[:acknowledged] }
        services_critical_ack = services.count { |s| s[:status] == 'CRITICAL' && s[:acknowledged] }
        services_pending = services.count { |s| s[:status] == 'PENDING' }

        service_health_pct = total_services > 0 ? ((services_ok.to_f / total_services) * 100).round(1) : 100.0

        {
          program_status: program_status,
          host_health_pct: host_health_pct,
          service_health_pct: service_health_pct,
          hosts: {
            total: total_hosts,
            up: hosts_up,
            down_unhandled: hosts_down_unhandled,
            down_ack: hosts_down_ack,
            unreachable: hosts_unreachable
          },
          services: {
            total: total_services,
            ok: services_ok,
            warning_unhandled: services_warning_unhandled,
            warning_ack: services_warning_ack,
            critical_unhandled: services_critical_unhandled,
            critical_ack: services_critical_ack,
            pending: services_pending
          }
        }
      end
    end
  end
end
