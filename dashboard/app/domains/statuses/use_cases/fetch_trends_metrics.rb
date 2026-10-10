module Statuses
  module UseCases
    class FetchTrendsMetrics
      def self.call(days: 7)
        duration_seconds = days * 86400
        alerts = Engines::NagiosEngine.alerts(duration_seconds: duration_seconds)

        daily_buckets = Services::TrendsCalculator.aggregate_daily(alerts: alerts, days: days)
        daily_stats = daily_buckets.map do |b|
          {
            date_str: b.date_str,
            date: b.date,
            ok_count: b.ok_count,
            warning_count: b.warning_count,
            critical_count: b.critical_count,
            total_alerts: b.total_alerts,
            health_ratio: b.health_ratio
          }
        end

        histogram = Statuses::Services::AlertHistogramCalculator.analyze(alerts)

        {
          days: days,
          daily_stats: daily_stats,
          histogram: histogram
        }
      end
    end
  end
end
