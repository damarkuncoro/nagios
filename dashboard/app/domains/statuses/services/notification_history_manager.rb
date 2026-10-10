# frozen_string_literal: true

require 'csv'
require 'time'

module Statuses
  module Services
    # Adopts notification history tracking and filtering from cgi/notifications.c & cgi/history.c
    # Filters notification audit trails by contact, host, service, or notification reason,
    # aggregates recipient delivery metrics, and formats CSV audit trail reports.
    class NotificationHistoryManager
      NotificationRecord = Struct.new(
        :timestamp,
        :host_name,
        :service_desc,
        :contact_name,
        :notification_type, # :host_notification or :service_notification
        :reason,            # PROBLEM, RECOVERY, ACKNOWLEDGEMENT, FLAPPINGSTART, etc.
        :state,
        :command_name,
        :output,
        keyword_init: true
      ) do
        def host_notification?
          notification_type == :host_notification || service_desc.nil? || service_desc.to_s.strip.empty?
        end

        def service_notification?
          !host_notification?
        end

        def problem?
          r = reason.to_s.upcase
          r == 'PROBLEM' || %w[CRITICAL DOWN WARNING UNREACHABLE].include?(state.to_s.upcase)
        end

        def recovery?
          r = reason.to_s.upcase
          r == 'RECOVERY' || %w[OK UP].include?(state.to_s.upcase)
        end

        def to_h
          {
            timestamp: timestamp,
            host_name: host_name,
            service_desc: service_desc,
            contact_name: contact_name,
            notification_type: notification_type,
            reason: reason,
            state: state,
            command_name: command_name,
            output: output
          }
        end
      end

      NotificationStats = Struct.new(
        :total,
        :host_total,
        :service_total,
        :problem_total,
        :recovery_total,
        :ack_total,
        :flapping_total,
        :downtime_total,
        :top_contacts,
        keyword_init: true
      )

      class << self
        def filter(notifications, options = {})
          new.filter(notifications, options)
        end

        def calculate_stats(notifications)
          new.calculate_stats(notifications)
        end

        def export_csv(notifications)
          new.export_csv(notifications)
        end
      end

      # Filters notification event records (cgi/notifications.c: display_notifications)
      def filter(notifications, options = {})
        items = Array(notifications).map { |n| normalize_record(n) }

        items.select do |n|
          record_passes_filter?(n, options)
        end
      end

      # Computes recipient and delivery statistics
      def calculate_stats(notifications)
        items = Array(notifications).map { |n| normalize_record(n) }
        contacts_count = Hash.new(0)

        host_tot = 0
        svc_tot = 0
        prob_tot = 0
        rec_tot = 0
        ack_tot = 0
        flap_tot = 0
        dt_tot = 0

        items.each do |n|
          n.host_notification? ? (host_tot += 1) : (svc_tot += 1)

          c_name = n.contact_name.to_s.strip
          contacts_count[c_name] += 1 unless c_name.empty?

          r = (n.reason || n.state).to_s.upcase
          if n.problem?
            prob_tot += 1
          elsif n.recovery?
            rec_tot += 1
          elsif r.include?('ACK')
            ack_tot += 1
          elsif r.include?('FLAP')
            flap_tot += 1
          elsif r.include?('DOWNTIME')
            dt_tot += 1
          end
        end

        sorted_contacts = contacts_count.sort_by { |_, count| -count }

        NotificationStats.new(
          total: items.size,
          host_total: host_tot,
          service_total: svc_tot,
          problem_total: prob_tot,
          recovery_total: rec_tot,
          ack_total: ack_tot,
          flapping_total: flap_tot,
          downtime_total: dt_tot,
          top_contacts: sorted_contacts
        )
      end

      # Exports notification events to CSV (RFC 4180 format)
      def export_csv(notifications)
        items = Array(notifications).map { |n| normalize_record(n) }

        CSV.generate(headers: true) do |csv|
          csv << [
            'Timestamp',
            'Host Name',
            'Service Description',
            'Contact Name',
            'Notification Type',
            'Reason / State',
            'Output'
          ]

          items.each do |n|
            ts_str = n.timestamp.is_a?(Time) ? n.timestamp.strftime('%Y-%m-%d %H:%M:%S') : n.timestamp.to_s
            csv << [
              ts_str,
              n.host_name,
              n.service_desc || 'HOST ALERT',
              n.contact_name,
              n.host_notification? ? 'HOST' : 'SERVICE',
              n.reason || n.state,
              n.output
            ]
          end
        end
      end

      private

      def normalize_record(raw)
        return raw if raw.is_a?(NotificationRecord)

        ts = get_attr(raw, :timestamp) || get_attr(raw, :time)
        parsed_ts = parse_time(ts)

        h_name = get_attr(raw, :host_name).to_s
        s_desc = (get_attr(raw, :service_desc) || get_attr(raw, :service_description)).to_s
        s_desc = nil if s_desc.strip.empty?

        type = s_desc.nil? ? :host_notification : :service_notification
        type_str = get_attr(raw, :notification_type).to_s.downcase
        type = :host_notification if type_str.include?('host')

        NotificationRecord.new(
          timestamp: parsed_ts,
          host_name: h_name,
          service_desc: s_desc,
          contact_name: get_attr(raw, :contact_name).to_s,
          notification_type: type,
          reason: (get_attr(raw, :reason) || get_attr(raw, :notification_type)).to_s,
          state: (get_attr(raw, :state) || get_attr(raw, :status)).to_s.upcase,
          command_name: get_attr(raw, :command_name).to_s,
          output: get_attr(raw, :output).to_s
        )
      end

      def record_passes_filter?(rec, opts)
        # Contact filter
        if opts[:contact] && !opts[:contact].to_s.strip.empty?
          return false unless rec.contact_name.to_s.downcase == opts[:contact].to_s.strip.downcase
        end

        # Host filter
        if opts[:host_name] && !opts[:host_name].to_s.strip.empty?
          return false unless rec.host_name.to_s.downcase == opts[:host_name].to_s.strip.downcase
        end

        # Service filter
        if opts[:service_desc] && !opts[:service_desc].to_s.strip.empty?
          return false unless rec.service_desc.to_s.downcase == opts[:service_desc].to_s.strip.downcase
        end

        # Type filter (:host or :service)
        if opts[:type]
          case opts[:type].to_sym
          when :host then return false unless rec.host_notification?
          when :service then return false unless rec.service_notification?
          end
        end

        # Keyword substring query
        if opts[:query] && !opts[:query].to_s.strip.empty?
          q = opts[:query].to_s.strip.downcase
          match = rec.host_name.to_s.downcase.include?(q) ||
                  rec.service_desc.to_s.downcase.include?(q) ||
                  rec.contact_name.to_s.downcase.include?(q) ||
                  rec.output.to_s.downcase.include?(q)
          return false unless match
        end

        true
      end

      def parse_time(val)
        return nil if val.nil?

        case val
        when Time then val
        when Numeric then val.to_i <= 0 ? nil : Time.at(val.to_i)
        when String
          begin
            Time.parse(val)
          rescue StandardError
            val.to_i > 0 ? Time.at(val.to_i) : nil
          end
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
