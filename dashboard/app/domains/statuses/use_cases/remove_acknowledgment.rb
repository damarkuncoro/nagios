module Statuses
  module UseCases
    class RemoveAcknowledgment
      def self.host(host_name)
        res = Engines::NagiosEngine.remove_host_acknowledgement(host_name)
        Events::Broker.publish(
          Events::Broker::ACKNOWLEDGEMENT,
          { host_name: host_name, service_desc: nil, action: 'removed' },
          source: 'dashboard'
        )
        res
      end

      def self.service(host_name, service_desc)
        res = Engines::NagiosEngine.remove_service_acknowledgement(host_name, service_desc)
        Events::Broker.publish(
          Events::Broker::ACKNOWLEDGEMENT,
          { host_name: host_name, service_desc: service_desc, action: 'removed' },
          source: 'dashboard'
        )
        res
      end
    end
  end
end
