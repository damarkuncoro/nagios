module Statuses
  module UseCases
    class AcknowledgeProblem
      def self.service(host_name, service_desc, author: "nagiosadmin", comment: "Acknowledged via Dashboard")
        Engines::NagiosEngine.acknowledge_service_problem(host_name, service_desc, author, comment)
      end
    end
  end
end
