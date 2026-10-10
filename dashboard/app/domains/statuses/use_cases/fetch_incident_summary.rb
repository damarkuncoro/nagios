module Statuses
  module UseCases
    class FetchIncidentSummary
      def self.call(duration_seconds: 86400, limit: 10)
        alerts = Engines::NagiosEngine.alerts(duration_seconds: duration_seconds) rescue []
        Services::AlertSummaryAggregator.analyze(alerts, limit: limit).to_h
      end
    end
  end
end
