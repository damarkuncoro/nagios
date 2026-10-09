module Statuses
  module UseCases
    class FetchServicegroups
      def self.call
        services = Engines::NagiosEngine.services.map(&:to_h)

        grouped = services.group_by do |svc|
          desc = svc[:description].to_s.downcase
          if desc.include?('http') || desc.include?('web')
            'Web Services'
          elsif desc.include?('disk') || desc.include?('partition') || desc.include?('swap')
            'Storage & Disk Services'
          elsif desc.include?('load') || desc.include?('proc') || desc.include?('user')
            'System Resources Services'
          elsif desc.include?('ping') || desc.include?('network')
            'Network Connectivity Services'
          else
            'General Infrastructure Services'
          end
        end

        grouped.map do |group_name, group_services|
          ok_count = group_services.count { |s| s[:status] == 'OK' }
          total = group_services.size
          {
            name: group_name,
            services: group_services,
            ok_count: ok_count,
            total_count: total,
            all_ok: ok_count == total
          }
        end
      end
    end
  end
end
