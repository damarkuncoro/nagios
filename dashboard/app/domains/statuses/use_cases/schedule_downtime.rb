module Statuses
  module UseCases
    class ScheduleDowntime
      def self.service(host_name, service_desc, duration_hours: 1, author: "nagiosadmin", comment: "Scheduled Maintenance")
        res = Engines::NagiosEngine.schedule_service_downtime(
          host_name,
          service_desc,
          duration_hours: duration_hours,
          author: author,
          comment: comment
        )
        Events::Broker.publish(
          Events::Broker::DOWNTIME,
          { host_name: host_name, service_desc: service_desc, duration_hours: duration_hours, author: author, comment: comment },
          source: 'dashboard'
        )
        res
      end

      def self.host(host_name, duration_hours: 1, author: "nagiosadmin", comment: "Scheduled Maintenance")
        res = Engines::NagiosEngine.schedule_host_downtime(
          host_name,
          duration_hours: duration_hours,
          author: author,
          comment: comment
        )
        Events::Broker.publish(
          Events::Broker::DOWNTIME,
          { host_name: host_name, service_desc: nil, duration_hours: duration_hours, author: author, comment: comment },
          source: 'dashboard'
        )
        res
      end

      def self.cluster(host_name, duration_hours: 2, author: "nagiosadmin", comment: "Scheduled Cluster Maintenance")
        res = Engines::NagiosEngine.schedule_host_and_services_downtime(
          host_name,
          duration_hours: duration_hours,
          author: author,
          comment: comment
        )
        Events::Broker.publish(
          Events::Broker::DOWNTIME,
          { host_name: host_name, cluster: true, duration_hours: duration_hours, author: author, comment: comment },
          source: 'dashboard'
        )
        res
      end
    end
  end
end
