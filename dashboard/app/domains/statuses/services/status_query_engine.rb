# frozen_string_literal: true

module Statuses
  module Services
    # Adopts comprehensive status querying, filtering & sorting engine from cgi/status.c
    # Implements property filtering (passes_host_properties_filter & passes_service_properties_filter),
    # unhandled problem isolation (accounting for ACK and scheduled downtime depth),
    # substring searching, multi-field sorting, and pagination.
    class StatusQueryEngine
      HostTotals = Struct.new(
        :total,
        :up,
        :down,
        :down_unhandled,
        :down_ack,
        :down_downtime,
        :unreachable,
        :unreachable_unhandled,
        :unreachable_ack,
        :unreachable_downtime,
        :pending,
        :flapping,
        keyword_init: true
      ) do
        def total_problems
          down + unreachable
        end

        def total_unhandled
          down_unhandled + unreachable_unhandled
        end
      end

      ServiceTotals = Struct.new(
        :total,
        :ok,
        :warning,
        :warning_unhandled,
        :warning_ack,
        :warning_downtime,
        :critical,
        :critical_unhandled,
        :critical_ack,
        :critical_downtime,
        :unknown,
        :unknown_unhandled,
        :unknown_ack,
        :unknown_downtime,
        :pending,
        :flapping,
        keyword_init: true
      ) do
        def total_problems
          warning + critical + unknown
        end

        def total_unhandled
          warning_unhandled + critical_unhandled + unknown_unhandled
        end
      end

      QueryResult = Struct.new(
        :items,
        :total_count,
        :filtered_count,
        :totals,
        keyword_init: true
      )

      class << self
        def filter_hosts(hosts, options = {})
          new.filter_hosts(hosts, options)
        end

        def filter_services(services, options = {})
          new.filter_services(services, options)
        end

        def calculate_host_totals(hosts)
          new.calculate_host_totals(hosts)
        end

        def calculate_service_totals(services)
          new.calculate_service_totals(services)
        end
      end

      # Filters, sorts and paginates hosts (cgi/status.c: show_host_detail)
      def filter_hosts(hosts, options = {})
        items = Array(hosts)
        totals = calculate_host_totals(items)

        filtered = items.select { |h| host_passes_filter?(h, options) }
        sorted = sort_hosts(filtered, options[:sort_by], options[:sort_order])
        paginated = paginate(sorted, options[:limit], options[:offset])

        QueryResult.new(
          items: paginated,
          total_count: items.size,
          filtered_count: sorted.size,
          totals: totals
        )
      end

      # Filters, sorts and paginates services (cgi/status.c: show_service_detail)
      def filter_services(services, options = {})
        items = Array(services)
        totals = calculate_service_totals(items)

        filtered = items.select { |s| service_passes_filter?(s, options) }
        sorted = sort_services(filtered, options[:sort_by], options[:sort_order])
        paginated = paginate(sorted, options[:limit], options[:offset])

        QueryResult.new(
          items: paginated,
          total_count: items.size,
          filtered_count: sorted.size,
          totals: totals
        )
      end

      # Computes host totals (cgi/status.c: show_host_status_totals)
      def calculate_host_totals(hosts)
        t = HostTotals.new(
          total: hosts.size,
          up: 0,
          down: 0,
          down_unhandled: 0,
          down_ack: 0,
          down_downtime: 0,
          unreachable: 0,
          unreachable_unhandled: 0,
          unreachable_ack: 0,
          unreachable_downtime: 0,
          pending: 0,
          flapping: 0
        )

        hosts.each do |h|
          st = (get_attr(h, :status) || 'UP').to_s.upcase
          ack = is_truthy?(get_attr(h, :acknowledged) || get_attr(h, :problem_has_been_acknowledged))
          dt = (get_attr(h, :scheduled_downtime_depth) || 0).to_i.positive?
          flap = is_truthy?(get_attr(h, :is_flapping) || get_attr(h, :flapping))

          t.flapping += 1 if flap

          case st
          when 'UP'
            t.up += 1
          when 'DOWN'
            t.down += 1
            if dt
              t.down_downtime += 1
            elsif ack
              t.down_ack += 1
            else
              t.down_unhandled += 1
            end
          when 'UNREACHABLE'
            t.unreachable += 1
            if dt
              t.unreachable_downtime += 1
            elsif ack
              t.unreachable_ack += 1
            else
              t.unreachable_unhandled += 1
            end
          when 'PENDING'
            t.pending += 1
          else
            t.up += 1
          end
        end

        t
      end

      # Computes service totals (cgi/status.c: show_service_status_totals)
      def calculate_service_totals(services)
        t = ServiceTotals.new(
          total: services.size,
          ok: 0,
          warning: 0,
          warning_unhandled: 0,
          warning_ack: 0,
          warning_downtime: 0,
          critical: 0,
          critical_unhandled: 0,
          critical_ack: 0,
          critical_downtime: 0,
          unknown: 0,
          unknown_unhandled: 0,
          unknown_ack: 0,
          unknown_downtime: 0,
          pending: 0,
          flapping: 0
        )

        services.each do |s|
          st = (get_attr(s, :status) || 'OK').to_s.upcase
          ack = is_truthy?(get_attr(s, :acknowledged) || get_attr(s, :problem_has_been_acknowledged))
          dt = (get_attr(s, :scheduled_downtime_depth) || 0).to_i.positive?
          flap = is_truthy?(get_attr(s, :is_flapping) || get_attr(s, :flapping))

          t.flapping += 1 if flap

          case st
          when 'OK'
            t.ok += 1
          when 'WARNING'
            t.warning += 1
            if dt
              t.warning_downtime += 1
            elsif ack
              t.warning_ack += 1
            else
              t.warning_unhandled += 1
            end
          when 'CRITICAL'
            t.critical += 1
            if dt
              t.critical_downtime += 1
            elsif ack
              t.critical_ack += 1
            else
              t.critical_unhandled += 1
            end
          when 'UNKNOWN'
            t.unknown += 1
            if dt
              t.unknown_downtime += 1
            elsif ack
              t.unknown_ack += 1
            else
              t.unknown_unhandled += 1
            end
          when 'PENDING'
            t.pending += 1
          else
            t.ok += 1
          end
        end

        t
      end

      private

      def host_passes_filter?(host, opts)
        st = (get_attr(host, :status) || 'UP').to_s.upcase
        ack = is_truthy?(get_attr(host, :acknowledged) || get_attr(host, :problem_has_been_acknowledged))
        dt = (get_attr(host, :scheduled_downtime_depth) || 0).to_i.positive?
        flap = is_truthy?(get_attr(host, :is_flapping) || get_attr(host, :flapping))

        # Status filter
        if opts[:status]
          expected = Array(opts[:status]).map { |s| s.to_s.upcase }
          return false unless expected.include?(st)
        end

        # Problem only filter
        return false if opts[:problem_only] && st == 'UP'

        # Unhandled only filter (cgi/status.c: unhandled problem)
        if opts[:unhandled_only]
          return false if st == 'UP' || ack || dt
        end

        # Flapping filter
        return false if opts.key?(:flapping) && flap != !!opts[:flapping]

        # Acknowledged filter
        return false if opts.key?(:acknowledged) && ack != !!opts[:acknowledged]

        # Scheduled downtime filter
        return false if opts.key?(:in_downtime) && dt != !!opts[:in_downtime]

        # State type filter
        if opts[:state_type]
          st_type = (get_attr(host, :state_type) || 'HARD').to_s.upcase
          return false if st_type != opts[:state_type].to_s.upcase
        end

        # Keyword search query
        if opts[:query] && !opts[:query].to_s.strip.empty?
          q = opts[:query].to_s.strip.downcase
          name = get_attr(host, :name).to_s.downcase
          output = get_attr(host, :plugin_output).to_s.downcase
          return false unless name.include?(q) || output.include?(q)
        end

        true
      end

      def service_passes_filter?(service, opts)
        st = (get_attr(service, :status) || 'OK').to_s.upcase
        ack = is_truthy?(get_attr(service, :acknowledged) || get_attr(service, :problem_has_been_acknowledged))
        dt = (get_attr(service, :scheduled_downtime_depth) || 0).to_i.positive?
        flap = is_truthy?(get_attr(service, :is_flapping) || get_attr(service, :flapping))

        # Status filter
        if opts[:status]
          expected = Array(opts[:status]).map { |s| s.to_s.upcase }
          return false unless expected.include?(st)
        end

        # Problem only filter
        return false if opts[:problem_only] && st == 'OK'

        # Unhandled only filter
        if opts[:unhandled_only]
          return false if st == 'OK' || ack || dt
        end

        # Flapping filter
        return false if opts.key?(:flapping) && flap != !!opts[:flapping]

        # Acknowledged filter
        return false if opts.key?(:acknowledged) && ack != !!opts[:acknowledged]

        # Scheduled downtime filter
        return false if opts.key?(:in_downtime) && dt != !!opts[:in_downtime]

        # Host name filter
        if opts[:host_name]
          h_name = get_attr(service, :host_name).to_s
          return false unless h_name == opts[:host_name].to_s
        end

        # State type filter
        if opts[:state_type]
          st_type = (get_attr(service, :state_type) || 'HARD').to_s.upcase
          return false if st_type != opts[:state_type].to_s.upcase
        end

        # Keyword search query
        if opts[:query] && !opts[:query].to_s.strip.empty?
          q = opts[:query].to_s.strip.downcase
          h_name = get_attr(service, :host_name).to_s.downcase
          desc = (get_attr(service, :description) || get_attr(service, :service_description)).to_s.downcase
          output = get_attr(service, :plugin_output).to_s.downcase
          return false unless h_name.include?(q) || desc.include?(q) || output.include?(q)
        end

        true
      end

      def sort_hosts(hosts, sort_by, sort_order)
        field = case sort_by.to_s.downcase
                when 'status' then :status
                when 'last_check' then :last_check
                when 'attempts', 'attempt' then :current_attempt
                else :name
                end
        desc = sort_order.to_s.downcase == 'desc'

        hosts.sort do |a, b|
          val_a = get_attr(a, field)
          val_b = get_attr(b, field)
          cmp = compare_values(val_a, val_b)
          desc ? -cmp : cmp
        end
      end

      def sort_services(services, sort_by, sort_order)
        field = case sort_by.to_s.downcase
                when 'status' then :status
                when 'description' then :description
                when 'last_check' then :last_check
                else :host_name
                end
        desc = sort_order.to_s.downcase == 'desc'

        services.sort do |a, b|
          val_a = get_attr(a, field)
          val_b = get_attr(b, field)
          cmp = compare_values(val_a, val_b)
          desc ? -cmp : cmp
        end
      end

      def compare_values(val_a, val_b)
        if val_a.nil? && val_b.nil?
          0
        elsif val_a.nil?
          1
        elsif val_b.nil?
          -1
        else
          val_a <=> val_b
        end
      end

      def paginate(items, limit, offset)
        return items if limit.nil? || limit.to_i <= 0

        lim = limit.to_i
        off = [offset.to_i, 0].max
        items.slice(off, lim) || []
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
