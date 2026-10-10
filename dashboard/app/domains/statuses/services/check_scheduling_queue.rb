# frozen_string_literal: true

require 'time'

module Statuses
  module Services
    # Adopts Check Scheduling Queue and Event Distribution from cgi/extinfo.c & base/events.c
    # Unifies Host and Service check queues, provides multi-attribute sorting,
    # and computes temporal queue spread and storm detection metrics.
    class CheckSchedulingQueue
      QueueItem = Struct.new(
        :type,
        :type_label,
        :host_name,
        :description,
        :status,
        :last_check,
        :next_check,
        :current_attempt,
        :max_attempts,
        :attempts,
        :checks_enabled,
        :latency,
        keyword_init: true
      ) do
        def host_check?
          type == :host_check
        end

        def service_check?
          type == :service_check
        end

        def due_in_seconds(now: Time.now)
          return 0 if next_check.nil?

          t_next = next_check.is_a?(Time) ? next_check : Time.at(next_check.to_i)
          t_now = now.is_a?(Time) ? now : Time.at(now.to_i)
          (t_next - t_now).to_i
        end

        def due_soon?(now: Time.now, threshold_seconds: 60)
          due_in_seconds(now: now) <= threshold_seconds
        end

        def [](key)
          send(key) if respond_to?(key)
        end

        def to_h
          {
            type: type,
            type_label: type_label,
            host_name: host_name,
            description: description,
            status: status,
            last_check: last_check,
            next_check: next_check,
            current_attempt: current_attempt,
            max_attempts: max_attempts,
            attempts: attempts,
            checks_enabled: checks_enabled,
            latency: latency
          }
        end
      end

      QueueDistribution = Struct.new(
        :total,
        :host_checks,
        :service_checks,
        :due_in_1m,
        :due_in_5m,
        :due_in_15m,
        :due_later,
        :check_storm_detected,
        :earliest_check,
        :latest_check,
        keyword_init: true
      ) do
        def [](key)
          send(key) if respond_to?(key)
        end
      end

      SORT_FIELDS = {
        'next_check' => :next_check,
        'last_check' => :last_check,
        'hostname' => :host_name,
        'host_name' => :host_name,
        'servicename' => :description,
        'description' => :description,
        'status' => :status
      }.freeze

      class << self
        def build_queue(hosts:, services:, filter: nil, sort_by: 'next_check', sort_order: :asc, now: Time.now)
          new.build_queue(
            hosts: hosts,
            services: services,
            filter: filter,
            sort_by: sort_by,
            sort_order: sort_order,
            now: now
          )
        end
      end

      def build_queue(hosts:, services:, filter: nil, sort_by: 'next_check', sort_order: :asc, now: Time.now)
        host_items = extract_host_items(hosts)
        service_items = extract_service_items(services)
        all_items = host_items + service_items

        metrics = calculate_distribution(all_items, now)
        filtered = filter_items(all_items, filter)
        sorted = sort_items(filtered, sort_by, sort_order)

        {
          items: sorted,
          metrics: metrics
        }
      end

      private

      def extract_host_items(hosts)
        result = []
        Array(hosts).each do |h|
          nxt = parse_time(get_attr(h, :next_check))
          next if nxt.nil?

          cur_att = (get_attr(h, :current_attempt) || 1).to_i
          max_att = (get_attr(h, :max_attempts) || 1).to_i
          lst = parse_time(get_attr(h, :last_check))

          result << QueueItem.new(
            type: :host_check,
            type_label: 'HOST CHECK',
            host_name: get_attr(h, :name).to_s,
            description: 'Host Alive Check',
            status: (get_attr(h, :status) || 'UP').to_s.upcase,
            last_check: lst,
            next_check: nxt,
            current_attempt: cur_att,
            max_attempts: max_att,
            attempts: "#{cur_att}/#{max_att}",
            checks_enabled: is_truthy?(get_attr(h, :checks_enabled)),
            latency: (get_attr(h, :latency) || 0.0).to_f
          )
        end
        result
      end

      def extract_service_items(services)
        result = []
        Array(services).each do |s|
          nxt = parse_time(get_attr(s, :next_check))
          next if nxt.nil?

          cur_att = (get_attr(s, :current_attempt) || 1).to_i
          max_att = (get_attr(s, :max_attempts) || 1).to_i
          lst = parse_time(get_attr(s, :last_check))

          result << QueueItem.new(
            type: :service_check,
            type_label: 'SERVICE CHECK',
            host_name: get_attr(s, :host_name).to_s,
            description: (get_attr(s, :description) || get_attr(s, :service_description)).to_s,
            status: (get_attr(s, :status) || 'OK').to_s.upcase,
            last_check: lst,
            next_check: nxt,
            current_attempt: cur_att,
            max_attempts: max_att,
            attempts: "#{cur_att}/#{max_att}",
            checks_enabled: is_truthy?(get_attr(s, :checks_enabled)),
            latency: (get_attr(s, :latency) || 0.0).to_f
          )
        end
        result
      end

      def calculate_distribution(items, now)
        t_now = now.is_a?(Time) ? now : Time.at(now.to_i)
        due_1m = 0
        due_5m = 0
        due_15m = 0
        due_later = 0
        host_count = 0
        service_count = 0

        times = []

        items.each do |item|
          item.host_check? ? (host_count += 1) : (service_count += 1)
          next_t = item.next_check
          times << next_t if next_t

          diff = (next_t - t_now).to_i

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

        times.sort!
        earliest = times.first
        latest = times.last

        QueueDistribution.new(
          total: items.size,
          host_checks: host_count,
          service_checks: service_count,
          due_in_1m: due_1m,
          due_in_5m: due_5m,
          due_in_15m: due_15m,
          due_later: due_later,
          check_storm_detected: due_1m > 25,
          earliest_check: earliest,
          latest_check: latest
        )
      end

      def filter_items(items, filter)
        f = filter.to_s.strip.downcase
        case f
        when 'host'
          items.select(&:host_check?)
        when 'service'
          items.select(&:service_check?)
        else
          items
        end
      end

      def sort_items(items, sort_by, sort_order)
        field = SORT_FIELDS[sort_by.to_s.downcase] || :next_check
        desc = sort_order.to_s.downcase == 'desc'

        items.sort do |a, b|
          val_a = a.send(field)
          val_b = b.send(field)

          cmp = if val_a.nil? && val_b.nil?
                  0
                elsif val_a.nil?
                  1
                elsif val_b.nil?
                  -1
                else
                  val_a <=> val_b
                end

          desc ? -cmp : cmp
        end
      end

      def parse_time(val)
        return nil if val.nil?

        case val
        when Time then val
        when Date, DateTime then val.to_time
        when Numeric
          val.to_i <= 0 ? nil : Time.at(val.to_i > 1_000_000_000_000 ? val.to_i / 1000 : val.to_i)
        when String
          s = val.strip
          return nil if s.empty? || s == '0'

          begin
            Time.parse(s)
          rescue StandardError
            val.to_i > 0 ? Time.at(val.to_i) : nil
          end
        else
          nil
        end
      end

      def is_truthy?(val)
        val == true || val == 1 || val.to_s == '1' || val.to_s.casecmp('true').zero?
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
