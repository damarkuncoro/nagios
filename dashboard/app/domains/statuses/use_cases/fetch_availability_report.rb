module Statuses
  module UseCases
    class FetchAvailabilityReport
      def self.call(duration_seconds: 86400)
        hosts = Engines::NagiosEngine.hosts.map(&:to_h)
        services = Engines::NagiosEngine.services.map(&:to_h)

        host_reports = hosts.map do |host|
          uptime_pct = host[:status] == 'UP' ? 100.0 : 0.0
          {
            name: host[:name],
            status: host[:status],
            availability_pct: uptime_pct,
            sla_met: uptime_pct >= 99.0
          }
        end

        service_reports = services.map do |svc|
          uptime_pct = svc[:status] == 'OK' ? 100.0 : (svc[:status] == 'WARNING' ? 95.0 : 0.0)
          {
            host_name: svc[:host_name],
            description: svc[:description],
            status: svc[:status],
            availability_pct: uptime_pct,
            sla_met: uptime_pct >= 99.0
          }
        end

        total_nodes = host_reports.size + service_reports.size
        overall_sla_pct = total_nodes > 0 ? ((host_reports.count { |h| h[:sla_met] } + service_reports.count { |s| s[:sla_met] }).to_f / total_nodes * 100).round(1) : 100.0

        {
          host_reports: host_reports,
          service_reports: service_reports,
          overall_sla_pct: overall_sla_pct
        }
      end
    end
  end
end
