# frozen_string_literal: true

module Statuses
  module Services
    # Adopts alert distribution and event frequency analysis from cgi/histogram.c and cgi/summary.c
    # Analyzes 24-hour time slots, day-of-week patterns, peak failure hours, and top problem producers.
    class AlertHistogramCalculator
      HourlySlot = Struct.new(:hour, :hour_label, :ok_count, :warning_count, :critical_count, :total, keyword_init: true)
      DaySlot = Struct.new(:day_index, :day_name, :warning_count, :critical_count, :total, keyword_init: true)

      HistogramReport = Struct.new(
        :total_alerts,
        :hourly_slots,
        :day_slots,
        :peak_hour,
        :peak_hour_label,
        :peak_hour_count,
        :warning_series,
        :critical_series,
        :recovery_series,
        :top_producers,
        keyword_init: true
      )

      DAY_NAMES = %w[Minggu Senin Selasa Rabu Kamis Jumat Sabtu].freeze

      class << self
        def analyze(alerts)
          new.analyze(alerts)
        end
      end

      # Analyzes raw alert event records (cgi/histogram.c: compute_histogram)
      def analyze(alerts)
        hourly_data = Array.new(24) { { ok: 0, warning: 0, critical: 0 } }
        day_data = Array.new(7) { { warning: 0, critical: 0 } }
        sources = Hash.new(0)
        total_count = 0

        Array(alerts).each do |alert|
          ts = extract_timestamp(alert)
          next unless ts

          total_count += 1
          hour = ts.hour
          wday = ts.wday
          state = (alert[:state] || alert['state']).to_s.upcase

          source_key = format_source(alert)
          sources[source_key] += 1 if source_key

          if %w[OK UP RECOVERY].include?(state)
            hourly_data[hour][:ok] += 1
          elsif state == 'WARNING'
            hourly_data[hour][:warning] += 1
            day_data[wday][:warning] += 1
          elsif %w[CRITICAL DOWN UNREACHABLE].include?(state)
            hourly_data[hour][:critical] += 1
            day_data[wday][:critical] += 1
          else
            hourly_data[hour][:warning] += 1
            day_data[wday][:warning] += 1
          end
        end

        # Build 24-hour hourly slots
        hourly_slots = (0..23).map do |h|
          label = sprintf('%02d:00', h)
          data = hourly_data[h]
          tot = data[:ok] + data[:warning] + data[:critical]
          HourlySlot.new(
            hour: h,
            hour_label: label,
            ok_count: data[:ok],
            warning_count: data[:warning],
            critical_count: data[:critical],
            total: tot
          )
        end

        # Build 7-day day slots
        day_slots = (0..6).map do |w|
          data = day_data[w]
          tot = data[:warning] + data[:critical]
          DaySlot.new(
            day_index: w,
            day_name: DAY_NAMES[w],
            warning_count: data[:warning],
            critical_count: data[:critical],
            total: tot
          )
        end

        # Find peak hour
        peak_slot = hourly_slots.max_by { |s| s.warning_count + s.critical_count } || hourly_slots.first

        # Top problem producers
        top_producers = sources.sort_by { |_, c| -c }.take(10).map do |name, count|
          { name: name, count: count, pct: total_count.positive? ? (count.to_f / total_count * 100).round(1) : 0.0 }
        end

        HistogramReport.new(
          total_alerts: total_count,
          hourly_slots: hourly_slots,
          day_slots: day_slots,
          peak_hour: peak_slot.hour,
          peak_hour_label: peak_slot.hour_label,
          peak_hour_count: peak_slot.warning_count + peak_slot.critical_count,
          warning_series: hourly_slots.map(&:warning_count),
          critical_series: hourly_slots.map(&:critical_count),
          recovery_series: hourly_slots.map(&:ok_count),
          top_producers: top_producers
        )
      end

      private

      def extract_timestamp(alert)
        raw_ts = alert[:timestamp] || alert['timestamp'] || alert[:time] || alert['time']
        return nil unless raw_ts

        if raw_ts.is_a?(Time) || raw_ts.is_a?(DateTime)
          raw_ts
        elsif raw_ts.is_a?(Integer) || raw_ts.is_a?(Float)
          Time.at(raw_ts)
        elsif raw_ts.is_a?(String)
          Time.parse(raw_ts) rescue nil
        end
      end

      def format_source(alert)
        h = alert[:host_name] || alert['host_name']
        s = alert[:service_description] || alert['service_description']
        return nil unless h

        s ? "#{h} / #{s}" : h
      end
    end
  end
end
