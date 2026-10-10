module Statuses
  module UseCases
    class FetchAvailabilityReport
      def self.call(duration_seconds: 86400)
        hosts = (Engines::NagiosEngine.hosts rescue []).map(&:to_h)
        services = (Engines::NagiosEngine.services rescue []).map(&:to_h)

        report = Statuses::Services::AvailabilityCalculator.calculate(
          hosts: hosts,
          services: services,
          window_seconds: duration_seconds
        )

        host_reports = report.host_reports.map do |hr|
          {
            name: hr.name,
            status: hr.status,
            availability_pct: hr.sla_availability_pct,
            raw_availability_pct: hr.raw_availability_pct,
            scheduled_downtime_seconds: hr.scheduled_downtime_seconds,
            sla_met: hr.sla_met
          }
        end

        service_reports = report.service_reports.map do |sr|
          {
            host_name: sr.host_name,
            description: sr.description,
            status: sr.status,
            availability_pct: sr.sla_availability_pct,
            raw_availability_pct: sr.raw_availability_pct,
            scheduled_downtime_seconds: sr.scheduled_downtime_seconds,
            sla_met: sr.sla_met
          }
        end

        {
          host_reports: host_reports,
          service_reports: service_reports,
          overall_sla_pct: report.overall_sla_pct,
          overall_raw_pct: report.overall_raw_pct
        }
      end
    end
  end
end
