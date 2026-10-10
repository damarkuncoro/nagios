# frozen_string_literal: true

module Statuses
  module Services
    # Adopts hierarchical network map layout and topology DAG resolution from cgi/statusmap.c
    # Builds multi-tier parent-child topology trees, computes layer depths,
    # detects isolated nodes, and resolves graph links for visual mapping.
    class NetworkTopologyBuilder
      TopologyNode = Struct.new(
        :name,
        :alias,
        :status,
        :address,
        :parents,
        :children,
        :tier,
        :plugin_output,
        :ok_services,
        :total_services,
        :is_root,
        :is_isolated,
        keyword_init: true
      ) do
        def up?
          status == 'UP'
        end

        def down?
          status == 'DOWN'
        end

        def unreachable?
          status == 'UNREACHABLE'
        end
      end

      TopologyGraph = Struct.new(
        :root_name,
        :nodes,
        :tiers,
        :links,
        :max_depth,
        :isolated_nodes,
        keyword_init: true
      )

      class << self
        def build(hosts:, services: [], host_objects: {})
          new.build(hosts: hosts, services: services, host_objects: host_objects)
        end
      end

      # Builds topology graph (cgi/statusmap.c: create_network_map)
      def build(hosts:, services: [], host_objects: {})
        nodes_map = {}
        child_links = Hash.new { |h, k| h[k] = [] }
        parent_map = {}

        # 1. Normalize host objects and extract parent links
        Array(hosts).each do |host|
          h_name = get_attr(host, :name) || get_attr(host, :host_name)
          next unless h_name

          cfg = find_host_config(h_name, host, host_objects)
          parents = extract_parents(cfg)
          parent_map[h_name] = parents

          parents.each do |p|
            child_links[p] << h_name
          end

          h_services = Array(services).select { |s| (get_attr(s, :host_name) || s[:host_name]) == h_name }
          ok_count = h_services.count { |s| (get_attr(s, :status) || s[:status]).to_s.upcase == 'OK' }

          nodes_map[h_name] = TopologyNode.new(
            name: h_name,
            alias: get_attr(host, :alias) || h_name,
            status: (get_attr(host, :status) || 'UP').to_s.upcase,
            address: get_attr(host, :address) || '127.0.0.1',
            parents: parents,
            children: [],
            tier: 1,
            plugin_output: get_attr(host, :plugin_output) || '',
            ok_services: ok_count,
            total_services: h_services.size,
            is_root: parents.empty?,
            is_isolated: false
          )
        end

        # 2. Populate children
        nodes_map.each do |name, node|
          node.children = child_links[name]
        end

        # 3. Calculate topological tiers (BFS from nodes without parents)
        tier_groups = Hash.new { |h, k| h[k] = [] }
        max_depth = 1

        nodes_map.each_value do |node|
          depth = calculate_depth(node.name, parent_map, nodes_map)
          node.tier = depth
          node.is_isolated = node.parents.empty? && node.children.empty?
          tier_groups[depth] << node
          max_depth = [max_depth, depth].max
        end

        # 4. Generate explicit link tuples
        links = []
        nodes_map.each do |name, node|
          node.parents.each do |p_name|
            if nodes_map.key?(p_name)
              links << { source: p_name, target: name }
            else
              # Virtual link from Master Nagios Engine
              links << { source: 'Nagios Core Master', target: name }
            end
          end
          # If node has no parents, connect directly to Master Engine
          links << { source: 'Nagios Core Master', target: name } if node.parents.empty?
        end

        TopologyGraph.new(
          root_name: 'Nagios Core Master',
          nodes: nodes_map.values,
          tiers: tier_groups,
          links: links,
          max_depth: max_depth,
          isolated_nodes: nodes_map.values.select(&:is_isolated)
        )
      end

      private

      def calculate_depth(name, parent_map, nodes_map, visited = {})
        return 1 if visited[name] # Cycle protection

        visited[name] = true
        parents = parent_map[name] || []
        return 1 if parents.empty?

        valid_parents = parents.select { |p| nodes_map.key?(p) }
        return 1 if valid_parents.empty?

        1 + valid_parents.map { |p| calculate_depth(p, parent_map, nodes_map, visited.dup) }.max
      end

      def find_host_config(name, host, host_objects)
        return host_objects[name] if host_objects.is_a?(Hash) && host_objects.key?(name)

        host
      end

      def extract_parents(data)
        return [] if data.nil?

        raw = if data.is_a?(Hash)
                data['parents'] || data[:parents]
              elsif data.respond_to?(:parents)
                data.parents
              end

        return [] if raw.nil?
        return raw if raw.is_a?(Array)

        raw.to_s.split(',').map(&:strip).reject(&:empty?)
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
