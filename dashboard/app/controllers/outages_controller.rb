class OutagesController < ApplicationController
  def index
    all_hosts = Engines::NagiosEngine.hosts.map(&:to_h)
    all_services = Engines::NagiosEngine.services.map(&:to_h)

    @blocking_hosts = all_hosts.select { |h| %w[DOWN UNREACHABLE].include?(h[:status]) }
    @total_outages = @blocking_hosts.size

    @outage_reports = @blocking_hosts.map do |host|
      impacted_svcs = all_services.select { |s| s[:host_name] == host[:name] }
      {
        host: host,
        impacted_services: impacted_svcs,
        severity: host[:status] == 'DOWN' ? 'CRITICAL' : 'HIGH'
      }
    end

    @total_impacted_services = @outage_reports.sum { |r| r[:impacted_services].size }
  end
end
