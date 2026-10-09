module Statuses
  module UseCases
    class ScheduleCheck
      def self.host(host_name)
        Engines::NagiosEngine.schedule_host_recheck(host_name)
      end

      def self.service(host_name, service_desc)
        Engines::NagiosEngine.schedule_service_recheck(host_name, service_desc)
      end
    end
  end
end
