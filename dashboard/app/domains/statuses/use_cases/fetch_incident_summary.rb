module Statuses
  module UseCases
    class FetchIncidentSummary
      def self.call(duration_seconds: 86400)
        alerts = Engines::NagiosEngine.alerts(duration_seconds: duration_seconds)

        host_failures = Hash.new(0)
        service_failures = Hash.new(0)

        alerts.each do |alert|
          state = alert[:state].to_s.upcase
          next if state == 'OK' || state == 'UP'

          host_name = alert[:host_name]
          service_desc = alert[:service_description]

          host_failures[host_name] += 1 if host_name.present?
          service_failures["#{host_name} / #{service_desc}"] += 1 if service_desc.present?
        end

        top_hosts = host_failures.sort_by { |_, count| -count }.take(10)
        top_services = service_failures.sort_by { |_, count| -count }.take(10)

        {
          total_alerts: alerts.size,
          top_hosts: top_hosts,
          top_services: top_services
        }
      end
    end
  end
end
