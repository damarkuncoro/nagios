module Statuses
  module UseCases
    class FetchNetworkMap
      def self.call
        hosts = (Engines::NagiosEngine.hosts rescue []).map(&:to_h)
        services = (Engines::NagiosEngine.services rescue []).map(&:to_h)
        host_objs = (Engines::NagiosEngine.host_objects rescue {})

        graph = Statuses::Services::NetworkTopologyBuilder.build(
          hosts: hosts,
          services: services,
          host_objects: host_objs
        )

        nodes = graph.nodes.map do |n|
          h_services = Array(services).select do |s|
            s_host = s.is_a?(Hash) ? (s[:host_name] || s['host_name']) : (s.respond_to?(:host_name) ? s.host_name : nil)
            s_host.to_s == n.name.to_s
          end

          {
            name: n.name,
            alias: n.alias,
            status: n.status,
            address: n.address,
            parents: n.parents,
            children: n.children,
            tier: n.tier,
            plugin_output: n.plugin_output,
            ok_services: n.ok_services,
            total_services: n.total_services,
            parent: n.parents.first || graph.root_name,
            services: h_services.map do |s|
              s_desc = s.is_a?(Hash) ? (s[:description] || s['description']) : (s.respond_to?(:description) ? s.description : '')
              s_st = s.is_a?(Hash) ? (s[:status] || s['status']) : (s.respond_to?(:status) ? s.status : 'OK')
              s_out = s.is_a?(Hash) ? (s[:plugin_output] || s['plugin_output']) : (s.respond_to?(:plugin_output) ? s.plugin_output : '')
              {
                description: s_desc.to_s,
                status: s_st.to_s.upcase,
                plugin_output: s_out.to_s
              }
            end
          }
        end

        {
          root: { name: graph.root_name, status: 'UP' },
          nodes: nodes,
          tiers: graph.tiers,
          links: graph.links,
          max_depth: graph.max_depth
        }
      end
    end
  end
end
