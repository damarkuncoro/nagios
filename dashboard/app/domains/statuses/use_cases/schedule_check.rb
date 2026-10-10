module Statuses
  module UseCases
    class ScheduleCheck
      def self.host(host_name)
        res = Engines::NagiosEngine.schedule_host_recheck(host_name)
        Events::Broker.publish(
          Events::Broker::CHECK,
          { host_name: host_name, service_desc: nil },
          source: 'dashboard'
        )
        res
      end

      def self.service(host_name, service_desc)
        res = Engines::NagiosEngine.schedule_service_recheck(host_name, service_desc)
        Events::Broker.publish(
          Events::Broker::CHECK,
          { host_name: host_name, service_desc: service_desc },
          source: 'dashboard'
        )
        res
      end
    end
  end
end
