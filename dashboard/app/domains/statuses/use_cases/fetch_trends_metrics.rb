module Statuses
  module UseCases
    class FetchTrendsMetrics
      def self.call(days: 7)
        duration_seconds = days * 86400
        alerts = Engines::NagiosEngine.alerts(duration_seconds: duration_seconds)

        daily_stats = (0...days).map do |i|
          date = Date.today - i
          date_str = date.strftime("%d %b")

          day_alerts = alerts.select do |a|
            a[:timestamp].to_date == date
          end

          ok_count = day_alerts.count { |a| %w[OK UP RECOVERY].include?(a[:state].to_s.upcase) }
          warning_count = day_alerts.count { |a| a[:state].to_s.upcase == 'WARNING' }
          critical_count = day_alerts.count { |a| %w[CRITICAL DOWN UNREACHABLE].include?(a[:state].to_s.upcase) }
          total_day_alerts = day_alerts.size

          health_ratio = total_day_alerts > 0 ? (((ok_count + 1).to_f / (total_day_alerts + 1)) * 100).round(1) : 100.0

          {
            date_str: date_str,
            date: date,
            ok_count: ok_count,
            warning_count: warning_count,
            critical_count: critical_count,
            total_alerts: total_day_alerts,
            health_ratio: health_ratio
          }
        end

        {
          days: days,
          daily_stats: daily_stats.reverse
        }
      end
    end
  end
end
