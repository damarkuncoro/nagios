module Statuses
  module UseCases
    class FetchTacticalOverview
      def self.call
        hosts = Engines::NagiosEngine.hosts.map(&:to_h)
        services = Engines::NagiosEngine.services.map(&:to_h)
        program_status = Engines::NagiosEngine.program_status

        Services::TacticalOverviewAggregator.aggregate(
          hosts: hosts,
          services: services,
          program_status: program_status
        ).to_h
      end
    end
  end
end
