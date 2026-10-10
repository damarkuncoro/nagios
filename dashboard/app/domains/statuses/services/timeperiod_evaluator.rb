# frozen_string_literal: true

module Statuses
  module Services
    # Adopts check_time_against_period from base/utils.c lines 1160-1250
    # Evaluates whether a given timestamp falls within active monitoring/notification timeperiod ranges.
    class TimeperiodEvaluator
      DAYS = %i[sunday monday tuesday wednesday thursday friday saturday].freeze

      class << self
        # Evaluates whether test_time falls within timeperiod ranges (base/utils.c: check_time_against_period)
        def active?(timeperiod, test_time: nil, all_periods: {})
          return true if timeperiod.nil?

          tp_data = if timeperiod.is_a?(String)
                      return true if timeperiod.downcase == '24x7'
                      all_periods[timeperiod] || { 'name' => timeperiod }
                    elsif timeperiod.is_a?(Hash)
                      timeperiod
                    else
                      timeperiod.respond_to?(:to_h) ? timeperiod.to_h : {}
                    end

          tp_name = (tp_data['name'] || tp_data[:name]).to_s.downcase
          return true if tp_name == '24x7'

          t = test_time || (Time.respond_to?(:current) ? Time.current : Time.now)

          # 1. Check exclusions (base/utils.c line 1181)
          exclusions = Array(tp_data['exclude'] || tp_data[:exclude] || tp_data['exclusions'] || tp_data[:exclusions]).compact
          exclusions.each do |ex_name|
            ex_tp = all_periods[ex_name.to_s]
            if ex_tp && active?(ex_tp, test_time: t, all_periods: all_periods)
              return false
            end
          end

          # 2. Check Day of Week timeranges
          day_name = DAYS[t.wday]
          ranges_str = tp_data[day_name.to_s] || tp_data[day_name] || tp_data[day_name.to_s.capitalize]

          # If no ranges defined for this specific day, check if standard 24x7 or default
          return false if ranges_str.blank?

          seconds_since_midnight = (t.hour * 3600) + (t.min * 60) + t.sec

          # Ranges can be comma-separated: "09:00-12:00, 13:00-17:00"
          timeranges = parse_timeranges(ranges_str)
          timeranges.any? do |r_start, r_end|
            seconds_since_midnight >= r_start && seconds_since_midnight <= r_end
          end
        end

        private

        def parse_timeranges(str)
          return [] if str.blank?

          str.to_s.split(',').map do |part|
            cleaned = part.strip
            if cleaned =~ /^(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})$/
              start_sec = ($1.to_i * 3600) + ($2.to_i * 60)
              end_sec   = ($3.to_i * 3600) + ($4.to_i * 60)
              end_sec = 86_400 if end_sec >= 86_400 || ($3.to_i == 24 && $4.to_i == 0)
              [start_sec, end_sec]
            end
          end.compact
        end
      end
    end
  end
end
