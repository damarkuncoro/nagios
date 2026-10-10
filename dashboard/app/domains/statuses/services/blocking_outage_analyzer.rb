# frozen_string_literal: true

module Statuses
  module Services
    # Adopts Network Outages root-cause analysis from cgi/outages.c
    # Traverses parent-child dependency trees, identifies primary root blocking hosts
    # versus downstream collateral failures, and calculates outage severity scores.
    class BlockingOutageAnalyzer
      DEFAULT_SEVERITY_DIVISOR = 4 # Default in cgi/outages.c: services are 1/4 as critical as hosts

      OutageReport = Struct.new(
        :host,
        :host_name,
        :status,
        :severity,
        :affected_child_hosts,
        :affected_child_services,
        :impacted_services,
        :blocking_parents,
        :root_cause,
        keyword_init: true
      ) do
        def root_cause?
          !!root_cause
        end

        def down?
          status.to_s.upcase == 'DOWN'
        end

        def unreachable?
          status.to_s.upcase == 'UNREACHABLE'
        end
      end

      OutageSummary = Struct.new(
        :outages,
        :total_blocking_outages,
        :total_affected_hosts,
        :total_affected_services,
        :network_health_pct,
        keyword_init: true
      )

      class << self
        def analyze(hosts:, services:, severity_divisor: DEFAULT_SEVERITY_DIVISOR)
          new(severity_divisor: severity_divisor).analyze(hosts: hosts, services: services)
        end
      end

      def initialize(severity_divisor: DEFAULT_SEVERITY_DIVISOR)
        @divisor = [severity_divisor.to_i, 1].max
      end

      def analyze(hosts:, services:)
        hosts_list = Array(hosts)
        services_list = Array(services)

        hosts_map = {}
        hosts_list.each do |h|
          name = get_attr(h, :name).to_s
          hosts_map[name] = h unless name.empty?
        end

        # Map services by host_name
        services_by_host = Hash.new { |h, k| h[k] = [] }
        services_list.each do |s|
          h_name = get_attr(s, :host_name).to_s
          services_by_host[h_name] << s unless h_name.empty?
        end

        # Map child hosts by parent
        children_by_parent = Hash.new { |h, k| h[k] = [] }
        hosts_map.each do |h_name, host|
          parents = parse_parents(host)
          parents.each do |p|
            children_by_parent[p] << h_name
          end
        end

        # Find problem hosts (DOWN or UNREACHABLE)
        problem_hosts = hosts_map.values.select do |h|
          st = get_status(h)
          st == 'DOWN' || st == 'UNREACHABLE'
        end

        # Identify blocking hosts (root failures)
        # In cgi/outages.c: a host is causing outages if it is DOWN/UNREACHABLE
        # and not blocked by an upstream parent, or if it has affected children
        outage_reports = []

        problem_hosts.each do |h|
          h_name = get_attr(h, :name).to_s
          blocked_upstream = route_blocked_upstream?(h, hosts_map)

          # Calculate affected children recursively
          visited = {}
          visited[h_name] = true
          child_hosts_count, child_svcs_count, impacted_svcs = calculate_effects(
            h_name,
            children_by_parent,
            services_by_host,
            visited
          )

          total_hosts_affected = child_hosts_count + 1
          direct_svcs = services_by_host[h_name] || []
          total_svcs_affected = child_svcs_count + direct_svcs.size
          all_impacted_svcs = (direct_svcs + impacted_svcs).uniq

          # Severity formula: cgi/outages.c lines 516-517
          severity = total_hosts_affected + (total_svcs_affected / @divisor)

          blocking_parents = find_blocking_parents(h, hosts_map)
          is_root = !blocked_upstream

          # Record outage report
          outage_reports << OutageReport.new(
            host: h,
            host_name: h_name,
            status: get_status(h),
            severity: severity,
            affected_child_hosts: total_hosts_affected,
            affected_child_services: total_svcs_affected,
            impacted_services: all_impacted_svcs,
            blocking_parents: blocking_parents,
            root_cause: is_root
          )
        end

        # Sort by severity descending (cgi/outages.c: sort_hostoutages)
        outage_reports.sort_by! { |r| -r.severity }

        total_blocking = outage_reports.count(&:root_cause?)
        total_aff_hosts = outage_reports.sum(&:affected_child_hosts)
        total_aff_svcs = outage_reports.sum(&:affected_child_services)

        total_hosts = hosts_map.size
        health_pct = if total_hosts.positive?
                       [((1.0 - (problem_hosts.size.to_f / total_hosts)) * 100).round(1), 0.0].max
                     else
                       100.0
                     end

        OutageSummary.new(
          outages: outage_reports,
          total_blocking_outages: total_blocking,
          total_affected_hosts: total_aff_hosts,
          total_affected_services: total_aff_svcs,
          network_health_pct: health_pct
        )
      end

      private

      # Tests whether route to host is blocked by upstream parents (cgi/outages.c: is_route_to_host_blocked)
      def route_blocked_upstream?(host, hosts_map)
        parents = parse_parents(host)
        return false if parents.empty?

        # If at least one parent is UP, route is not blocked
        parents.all? do |p_name|
          p_host = hosts_map[p_name]
          next false if p_host.nil?

          st = get_status(p_host)
          st == 'DOWN' || st == 'UNREACHABLE'
        end
      end

      def find_blocking_parents(host, hosts_map)
        parents = parse_parents(host)
        parents.select do |p_name|
          p_host = hosts_map[p_name]
          if p_host
            st = get_status(p_host)
            st == 'DOWN' || st == 'UNREACHABLE'
          else
            false
          end
        end
      end

      def calculate_effects(parent_name, children_map, services_map, visited)
        children = children_map[parent_name] || []
        hosts_count = 0
        svcs_count = 0
        impacted_svcs = []

        children.each do |child_name|
          next if visited[child_name]

          visited[child_name] = true
          hosts_count += 1

          child_svcs = services_map[child_name] || []
          svcs_count += child_svcs.size
          impacted_svcs.concat(child_svcs)

          c_hosts, c_svcs, c_imp_svcs = calculate_effects(child_name, children_map, services_map, visited)
          hosts_count += c_hosts
          svcs_count += c_svcs
          impacted_svcs.concat(c_imp_svcs)
        end

        [hosts_count, svcs_count, impacted_svcs]
      end

      def parse_parents(host)
        raw = get_attr(host, :parents) || get_attr(host, :parent_hosts)
        case raw
        when Array
          raw.map(&:to_s).reject(&:empty?)
        when String
          raw.split(',').map(&:strip).reject(&:empty?)
        else
          []
        end
      end

      def get_status(host)
        (get_attr(host, :status) || 'UP').to_s.upcase
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
