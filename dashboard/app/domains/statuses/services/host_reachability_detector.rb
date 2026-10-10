# frozen_string_literal: true

module Statuses
  module Services
    # Adopts determine_host_reachability algorithm from base/checks.c lines 3360-3404
    # Determines whether a failing host is DOWN or UNREACHABLE based on network parent topology.
    class HostReachabilityDetector
      HOST_UP          = 0
      HOST_DOWN        = 1
      HOST_UNREACHABLE = 2

      ReachabilityResult = Struct.new(
        :state_code,
        :state_name,
        :reachability,
        :blocking_parents,
        :available_parents,
        keyword_init: true
      ) do
        def up?
          state_code == HOST_UP
        end

        def down?
          state_code == HOST_DOWN
        end

        def unreachable?
          state_code == HOST_UNREACHABLE
        end
      end

      class << self
        # Evaluates single host reachability against its parent states
        # Mirrors determine_host_reachability in base/checks.c
        def determine_reachability(current_state:, parent_states: [], passive: false)
          curr_code = normalize_state_code(current_state)

          # 1. If host is UP, no translation needed
          if curr_code == HOST_UP
            return ReachabilityResult.new(
              state_code: HOST_UP,
              state_name: 'UP',
              reachability: :reachable,
              blocking_parents: [],
              available_parents: []
            )
          end

          # 2. Passive check with UNREACHABLE state stays UNREACHABLE
          if passive && curr_code == HOST_UNREACHABLE
            return ReachabilityResult.new(
              state_code: HOST_UNREACHABLE,
              state_name: 'UNREACHABLE',
              reachability: :unreachable,
              blocking_parents: [],
              available_parents: []
            )
          end

          # 3. If host has no parents defined, it is directly adjacent to monitoring server -> DOWN
          parent_list = Array(parent_states).compact
          if parent_list.empty?
            return ReachabilityResult.new(
              state_code: HOST_DOWN,
              state_name: 'DOWN',
              reachability: :down_direct,
              blocking_parents: [],
              available_parents: []
            )
          end

          # 4. Check all parent hosts
          up_parents = []
          down_parents = []

          parent_list.each do |p|
            p_code = p.is_a?(Hash) ? normalize_state_code(p[:status] || p['status']) : normalize_state_code(p)
            p_name = p.is_a?(Hash) ? (p[:name] || p['name']) : p.to_s

            if p_code == HOST_UP
              up_parents << p_name
            else
              down_parents << p_name
            end
          end

          # If at least one parent is UP, upstream route is clear -> host itself is DOWN
          if up_parents.any?
            ReachabilityResult.new(
              state_code: HOST_DOWN,
              state_name: 'DOWN',
              reachability: :down_route_available,
              blocking_parents: down_parents,
              available_parents: up_parents
            )
          else
            # No parents are UP -> network path severed upstream -> UNREACHABLE
            ReachabilityResult.new(
              state_code: HOST_UNREACHABLE,
              state_name: 'UNREACHABLE',
              reachability: :unreachable_path_blocked,
              blocking_parents: down_parents,
              available_parents: []
            )
          end
        end

        # Resolves reachability across entire cluster map (useful for Root Cause & Outages report)
        def analyze_cluster(hosts_map)
          results = {}

          hosts_map.each do |host_name, host_data|
            data = host_data.is_a?(Hash) ? host_data : (host_data.respond_to?(:to_h) ? host_data.to_h : {})
            parents = (data['parents'] || data[:parents] || data['parent_hosts'] || data[:parent_hosts] || [])

            parent_states = parents.map do |p_name|
              p_node = hosts_map[p_name]
              p_data = p_node.is_a?(Hash) ? p_node : (p_node.respond_to?(:to_h) ? p_node.to_h : {})
              {
                name: p_name,
                status: p_data[:status] || p_data['status'] || p_data[:status_code] || 0
              }
            end

            curr_st = data[:status] || data['status'] || data[:status_code] || 0
            results[host_name] = determine_reachability(
              current_state: curr_st,
              parent_states: parent_states
            )
          end

          results
        end

        private

        def normalize_state_code(state)
          case state.to_s.upcase
          when '0', 'UP', 'OK' then HOST_UP
          when '1', 'DOWN', 'WARNING' then HOST_DOWN
          when '2', 'UNREACHABLE', 'CRITICAL' then HOST_UNREACHABLE
          else
            state.to_i rescue HOST_DOWN
          end
        end
      end
    end
  end
end
