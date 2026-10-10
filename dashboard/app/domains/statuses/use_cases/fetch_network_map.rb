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
            parent: n.parents.first || graph.root_name
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
