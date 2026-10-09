module Statuses
  module UseCases
    class FetchNetworkMap
      def self.call
        hosts = Engines::NagiosEngine.hosts.map(&:to_h)
        services = Engines::NagiosEngine.services.map(&:to_h)

        nodes = hosts.map do |host|
          host_services = services.select { |s| s[:host_name] == host[:name] }
          ok_count = host_services.count { |s| s[:status] == 'OK' }
          total_services = host_services.size

          {
            name: host[:name],
            status: host[:status],
            plugin_output: host[:plugin_output],
            ok_services: ok_count,
            total_services: total_services,
            parent: 'Nagios Core Server'
          }
        end

        {
          root: { name: 'Nagios Core Server', status: 'UP' },
          nodes: nodes
        }
      end
    end
  end
end
