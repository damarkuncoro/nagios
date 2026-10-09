module Statuses
  module UseCases
    class ScheduleDowntime
      def self.service(host_name, service_desc, duration_hours: 1, author: "nagiosadmin", comment: "Scheduled Maintenance")
        Engines::NagiosEngine.schedule_service_downtime(
          host_name,
          service_desc,
          duration_hours: duration_hours,
          author: author,
          comment: comment
        )
      end
    end
  end
end
