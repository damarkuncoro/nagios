# frozen_string_literal: true

require 'time'

module Statuses
  module Services
    # Adopts alert summary reporting from cgi/summary.c
    # Analyzes historical alert event streams, groups top problem producers
    # (hosts and services), calculates HARD vs SOFT state distribution,
    # and calculates cluster alert share percentages.
    class AlertSummaryAggregator
      AlertProducer = Struct.new(
        :name,
        :host_name,
        :service_description,
        :type, # :host or :service
        :total_alerts,
        :warning_count,
        :critical_count,
        :unknown_count,
        :recovery_count,
        :share_pct,
        keyword_init: true
      ) do
        def host?
          type == :host
        end

        def service?
          type == :service
        end
      end

      AlertTotals = Struct.new(
        :total,
        :host_total,
        :service_total,
        :hard_total,
        :soft_total,
        :recovery_total,
        :warning_total,
        :critical_total,
        :unknown_total,
        keyword_init: true
      ) do
        def [](key)
          send(key) if respond_to?(key)
        end
      end

      SummaryReport = Struct.new(
        :totals,
        :top_hosts,
        :top_services,
        :top_host_producers,
        :top_service_producers,
        :recent_alerts,
        keyword_init: true
      ) do
        def to_h
          {
            total_alerts: totals.total,
            totals: totals,
            top_hosts: top_hosts,
            top_services: top_services,
            top_host_producers: top_host_producers,
            top_service_producers: top_service_producers,
            recent_alerts: recent_alerts
          }
        end

        def [](key)
          to_h[key]
        end
      end

      class << self
        def analyze(alerts, limit: 10)
          new.analyze(alerts, limit: limit)
        end
      end

      def analyze(alerts, limit: 10)
        alerts_list = Array(alerts)
        total_count = alerts_list.size

        totals = calculate_totals(alerts_list)

        host_producers_map = {}
        svc_producers_map = {}

        alerts_list.each do |alert|
          h_name = get_attr(alert, :host_name).to_s.strip
          s_desc = (get_attr(alert, :service_description) || get_attr(alert, :description)).to_s.strip
          state = (get_attr(alert, :state) || get_attr(alert, :status)).to_s.upcase

          # Track host producer
          unless h_name.empty?
            hp = (host_producers_map[h_name] ||= init_producer(h_name, h_name, nil, :host))
            update_producer_counts(hp, state)
          end

          # Track service producer
          if !h_name.empty? && !s_desc.empty?
            svc_key = "#{h_name} / #{s_desc}"
            sp = (svc_producers_map[svc_key] ||= init_producer(svc_key, h_name, s_desc, :service))
            update_producer_counts(sp, state)
          end
        end

        # Calculate share percentages & sort
        sorted_host_producers = host_producers_map.values.sort_by { |p| -p.total_alerts }
        sorted_svc_producers = svc_producers_map.values.sort_by { |p| -p.total_alerts }

        total_problem_alerts = [totals.warning_total + totals.critical_total + totals.unknown_total, 1].max

        sorted_host_producers.each do |p|
          p.share_pct = ((p.total_alerts.to_f / total_problem_alerts) * 100).round(1)
        end

        sorted_svc_producers.each do |p|
          p.share_pct = ((p.total_alerts.to_f / total_problem_alerts) * 100).round(1)
        end

        top_h_producers = sorted_host_producers.take(limit)
        top_s_producers = sorted_svc_producers.take(limit)

        # Backwards compatible tuples [name, count]
        top_hosts_tuples = top_h_producers.map { |p| [p.name, p.total_alerts] }
        top_services_tuples = top_s_producers.map { |p| [p.name, p.total_alerts] }

        recent = alerts_list.take(25)

        SummaryReport.new(
          totals: totals,
          top_hosts: top_hosts_tuples,
          top_services: top_services_tuples,
          top_host_producers: top_h_producers,
          top_service_producers: top_s_producers,
          recent_alerts: recent
        )
      end

      private

      def calculate_totals(alerts)
        tot = AlertTotals.new(
          total: alerts.size,
          host_total: 0,
          service_total: 0,
          hard_total: 0,
          soft_total: 0,
          recovery_total: 0,
          warning_total: 0,
          critical_total: 0,
          unknown_total: 0
        )

        alerts.each do |a|
          s_desc = (get_attr(a, :service_description) || get_attr(a, :description)).to_s.strip
          s_desc.empty? ? (tot.host_total += 1) : (tot.service_total += 1)

          st_type = get_attr(a, :state_type).to_s.upcase
          st_type == 'HARD' ? (tot.hard_total += 1) : (tot.soft_total += 1)

          state = (get_attr(a, :state) || get_attr(a, :status)).to_s.upcase
          case state
          when 'OK', 'UP', 'RECOVERY'
            tot.recovery_total += 1
          when 'WARNING'
            tot.warning_total += 1
          when 'CRITICAL', 'DOWN'
            tot.critical_total += 1
          when 'UNKNOWN', 'UNREACHABLE'
            tot.unknown_total += 1
          end
        end

        tot
      end

      def init_producer(name, host_name, service_desc, type)
        AlertProducer.new(
          name: name,
          host_name: host_name,
          service_description: service_desc,
          type: type,
          total_alerts: 0,
          warning_count: 0,
          critical_count: 0,
          unknown_count: 0,
          recovery_count: 0,
          share_pct: 0.0
        )
      end

      def update_producer_counts(producer, state)
        # Exclude pure recoveries from "problem" count in summary
        case state
        when 'WARNING'
          producer.total_alerts += 1
          producer.warning_count += 1
        when 'CRITICAL', 'DOWN'
          producer.total_alerts += 1
          producer.critical_count += 1
        when 'UNKNOWN', 'UNREACHABLE'
          producer.total_alerts += 1
          producer.unknown_count += 1
        when 'OK', 'UP', 'RECOVERY'
          producer.recovery_count += 1
        end
      end

      def get_attr(target, key)
        return nil if target.nil?

        if target.is_a?(Hash)
          target[key.to_s] || target[key.to_sym]
        elsif target.respond_to?(key)
          target.send(key)
        end
      end
    end
  end
end
