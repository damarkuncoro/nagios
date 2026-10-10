# frozen_string_literal: true

module Statuses
  module UseCases
    # Adopts event scheduling & distribution logic from base/events.c
    # Unifies Host & Service check queues and calculates check spread analytics
    class FetchSchedulingQueue
      def self.call(...)
        new(...).call
      end

      def initialize(engine: Engines::NagiosEngine, filter: nil, now: Time.current)
        @engine = engine
        @filter = filter.to_s.presence
        @now = now
      end

      def call
        host_items = build_host_queue
        service_items = build_service_queue

        all_items = (host_items + service_items).sort_by { |item| item[:next_check] }

        metrics = calculate_distribution_metrics(all_items)
        filtered_items = apply_filter(all_items)

        {
          items: filtered_items,
          metrics: metrics
        }
      end

      private

      def build_host_queue
        hosts = @engine.hosts rescue []
        hosts.filter_map do |h|
          next unless h.respond_to?(:next_check) && h.next_check.present?

          {
            type: :host_check,
            type_label: 'HOST CHECK',
            host_name: h.name,
            description: 'Host Alive Check',
            status: h.status,
            next_check: h.next_check,
            current_attempt: h.current_attempt,
            max_attempts: h.max_attempts,
            attempts: "#{h.current_attempt}/#{h.max_attempts}"
          }
        end
      end

      def build_service_queue
        services = @engine.services rescue []
        services.filter_map do |s|
          next unless s.respond_to?(:next_check) && s.next_check.present?

          {
            type: :service_check,
            type_label: 'SERVICE CHECK',
            host_name: s.host_name,
            description: s.description,
            status: s.status,
            next_check: s.next_check,
            latency: s.latency,
            attempts: s.attempts
          }
        end
      end

      def calculate_distribution_metrics(items)
        due_1m = 0
        due_5m = 0
        due_15m = 0
        due_later = 0
        host_count = 0
        service_count = 0

        items.each do |item|
          item[:type] == :host_check ? (host_count += 1) : (service_count += 1)
          diff = item[:next_check] - @now

          if diff <= 60
            due_1m += 1
          elsif diff <= 300
            due_5m += 1
          elsif diff <= 900
            due_15m += 1
          else
            due_later += 1
          end
        end

        {
          total: items.size,
          host_checks: host_count,
          service_checks: service_count,
          due_in_1m: due_1m,
          due_in_5m: due_5m,
          due_in_15m: due_15m,
          due_later: due_later,
          check_storm_detected: due_1m > 25
        }
      end

      def apply_filter(items)
        case @filter
        when 'host'
          items.select { |i| i[:type] == :host_check }
        when 'service'
          items.select { |i| i[:type] == :service_check }
        else
          items
        end
      end
    end
  end
end
