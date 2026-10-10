module Statuses
  module UseCases
    class AcknowledgeProblem
      def self.service(host_name, service_desc, author: "nagiosadmin", comment: "Acknowledged via Dashboard")
        res = Engines::NagiosEngine.acknowledge_service_problem(host_name, service_desc, author, comment)
        Events::Broker.publish(
          Events::Broker::ACKNOWLEDGEMENT,
          { host_name: host_name, service_desc: service_desc, author: author, comment: comment },
          source: 'dashboard'
        )
        res
      end

      def self.host(host_name, author: "nagiosadmin", comment: "Acknowledged via Dashboard")
        res = Engines::NagiosEngine.acknowledge_host_problem(host_name, author: author, comment: comment)
        Events::Broker.publish(
          Events::Broker::ACKNOWLEDGEMENT,
          { host_name: host_name, service_desc: nil, author: author, comment: comment },
          source: 'dashboard'
        )
        res
      end
    end
  end
end
