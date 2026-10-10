module Statuses
  module UseCases
    class FetchIncidentSummary
      def self.call(duration_seconds: 86400, limit: 10)
        alerts = begin
          Engines::NagiosEngine.alerts(duration_seconds: duration_seconds)
        rescue StandardError
          []
        end
        summary = Services::AlertSummaryAggregator.analyze(alerts, limit: limit).to_h
        histogram = Services::AlertHistogramCalculator.analyze(alerts)
        summary.merge(histogram: histogram)
      end
    end
  end
end
