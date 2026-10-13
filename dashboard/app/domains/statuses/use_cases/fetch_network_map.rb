module Statuses
  module UseCases
    class FetchNetworkMap
      def self.call
        hosts = (Engines::NagiosEngine.hosts rescue []).map(&:to_h)
        services = (Engines::NagiosEngine.services rescue []).map(&:to_h)
        host_objs = (Engines::NagiosEngine.host_objects rescue {})

        # If runtime engine only returns standalone default localhost, enrich with configured network topology
        host_names = hosts.map { |h| (h[:name] || h['name'] || h[:host_name] || h['host_name']).to_s }
        if host_names == ['localhost']
          cfg_path = ENV.fetch('NAGIOS_CONFIG_FILE', Rails.root.join('config/nagios_sample.cfg').to_s)
          catalog = Statuses::Services::ObjectConfigParser.parse_file(cfg_path) rescue nil
          if catalog&.hosts&.any?
            host_objs = catalog.hosts.merge(host_objs)
            snap_path = [ENV['NAGIOS_STATUS_FILE'], '/nagios_var/status.dat', Rails.root.join('tmp/status.dat').to_s].compact.find { |f| File.exist?(f) }
            snap = Statuses::Services::StatusDataParser.parse_file(snap_path) if snap_path rescue nil

            catalog.hosts.each do |h_name, h_cfg|
              next if h_name == 'localhost'

              h_cfg_hash = h_cfg.is_a?(Hash) ? h_cfg : (h_cfg.respond_to?(:to_h) ? h_cfg.to_h : {})
              snap_h = snap&.hosts&.dig(h_name) || {}
              st = case snap_h['current_state'].to_i
                   when 0 then 'UP'
                   when 1 then 'DOWN'
                   when 2 then 'UNREACHABLE'
                   else 'UP'
                   end

              hosts << {
                name: h_name,
                alias: h_cfg_hash['alias'] || h_cfg_hash[:alias] || h_name,
                status: st,
                address: h_cfg_hash['address'] || h_cfg_hash[:address] || '127.0.0.1',
                plugin_output: snap_h['plugin_output'].presence || 'Active network node'
              }

              # Enrich child services from snapshot
              snap_services = snap&.services&.dig(h_name) || {}
              snap_services.each do |s_desc, s_info|
                s_st = case s_info['current_state'].to_i
                       when 0 then 'OK'
                       when 1 then 'WARNING'
                       when 2 then 'CRITICAL'
                       else 'UNKNOWN'
                       end
                services << {
                  host_name: h_name,
                  description: s_desc,
                  status: s_st,
                  plugin_output: s_info['plugin_output'] || ''
                }
              end
            end
          end
        end

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
