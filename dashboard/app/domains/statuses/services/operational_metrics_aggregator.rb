# frozen_string_literal: true

module Statuses
  module Services
    # Adopts statistics aggregation routines from base/nagiostats.c
    # Computes latency averages, execution time bounds, and cluster health distributions.
    class OperationalMetricsAggregator
      OperationalSummary = Struct.new(
        :hosts,
        :services,
        :latency,
        :execution_time,
        :health_percentage,
        :total_objects,
        :flapping_objects,
        :downtime_objects,
        keyword_init: true
      )

      class << self
        def aggregate(hosts: [], services: [])
          hosts_list = hosts.is_a?(Hash) ? hosts.values : Array(hosts)
          services_list = flatten_services(services)

          h_stats = compute_host_stats(hosts_list)
          s_stats = compute_service_stats(services_list)

          all_latencies = extract_numbers(hosts_list, :latency) + extract_numbers(services_list, :latency)
          all_exectimes = extract_numbers(hosts_list, :execution_time) + extract_numbers(services_list, :execution_time)

          latency_stats = compute_distribution(all_latencies)
          exectime_stats = compute_distribution(all_exectimes)

          total_objs = h_stats[:total] + s_stats[:total]
          healthy_objs = h_stats[:up] + s_stats[:ok]
          health_pct = total_objs.positive? ? ((healthy_objs.to_f / total_objs) * 100.0).round(1) : 100.0

          flapping_total = h_stats[:flapping] + s_stats[:flapping]
          downtime_total = h_stats[:in_downtime] + s_stats[:in_downtime]

          OperationalSummary.new(
            hosts: h_stats,
            services: s_stats,
            latency: latency_stats,
            execution_time: exectime_stats,
            health_percentage: health_pct,
            total_objects: total_objs,
            flapping_objects: flapping_total,
            downtime_objects: downtime_total
          )
        end

        private

        def compute_host_stats(hosts)
          stats = {
            total: hosts.size,
            up: 0,
            down: 0,
            unreachable: 0,
            acknowledged: 0,
            flapping: 0,
            in_downtime: 0,
            active_checks: 0
          }

          hosts.each do |h|
            data = h.is_a?(Hash) ? h : (h.respond_to?(:to_h) ? h.to_h : {})
            st = (data[:status] || data['status'] || data[:status_code] || 0).to_i

            case st
            when 0 then stats[:up] += 1
            when 1 then stats[:down] += 1
            when 2 then stats[:unreachable] += 1
            else stats[:down] += 1
            end

            stats[:acknowledged] += 1 if is_truthy?(data[:acknowledged] || data['acknowledged'])
            stats[:flapping] += 1 if is_truthy?(data[:flapping] || data['is_flapping'])
            stats[:in_downtime] += 1 if (data[:scheduled_downtime_depth] || data['scheduled_downtime_depth']).to_i.positive?
            stats[:active_checks] += 1 if data[:checks_enabled] != false && data['checks_enabled'] != false
          end

          stats
        end

        def compute_service_stats(services)
          stats = {
            total: services.size,
            ok: 0,
            warning: 0,
            critical: 0,
            unknown: 0,
            acknowledged: 0,
            flapping: 0,
            in_downtime: 0,
            active_checks: 0
          }

          services.each do |s|
            data = s.is_a?(Hash) ? s : (s.respond_to?(:to_h) ? s.to_h : {})
            st = (data[:status] || data['status'] || data[:status_code] || 0).to_i

            case st
            when 0 then stats[:ok] += 1
            when 1 then stats[:warning] += 1
            when 2 then stats[:critical] += 1
            when 3 then stats[:unknown] += 1
            else stats[:unknown] += 1
            end

            stats[:acknowledged] += 1 if is_truthy?(data[:acknowledged] || data['acknowledged'])
            stats[:flapping] += 1 if is_truthy?(data[:flapping] || data['is_flapping'])
            stats[:in_downtime] += 1 if (data[:scheduled_downtime_depth] || data['scheduled_downtime_depth']).to_i.positive?
            stats[:active_checks] += 1 if data[:checks_enabled] != false && data['checks_enabled'] != false
          end

          stats
        end

        def compute_distribution(numbers)
          return { min: 0.0, max: 0.0, avg: 0.0 } if numbers.empty?

          min = numbers.min.to_f.round(3)
          max = numbers.max.to_f.round(3)
          avg = (numbers.sum.to_f / numbers.size).round(3)

          { min: min, max: max, avg: avg }
        end

        def extract_numbers(list, field)
          list.map do |item|
            data = item.is_a?(Hash) ? item : (item.respond_to?(:to_h) ? item.to_h : {})
            val = data[field] || data[field.to_s]
            val.to_f if val.present? && val.to_f.positive?
          end.compact
        end

        def flatten_services(services)
          if services.is_a?(Hash)
            list = []
            services.each_value do |s_group|
              if s_group.is_a?(Hash)
                list.concat(s_group.values)
              elsif s_group.is_a?(Array)
                list.concat(s_group)
              end
            end
            list
          else
            Array(services)
          end
        end

        def is_truthy?(val)
          val == true || val.to_s == '1'
        end
      end
    end
  end
end
