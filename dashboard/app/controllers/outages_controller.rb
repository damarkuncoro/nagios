class OutagesController < ApplicationController
  def index
    all_hosts = (Engines::NagiosEngine.hosts rescue []).map(&:to_h)
    all_services = (Engines::NagiosEngine.services rescue []).map(&:to_h)

    summary = Statuses::Services::BlockingOutageAnalyzer.analyze(
      hosts: all_hosts,
      services: all_services
    )

    @blocking_outage_summary = summary
    @total_outages = summary.total_blocking_outages
    @total_impacted_services = summary.total_affected_services

    hosts_map = all_hosts.each_with_object({}) { |h, acc| acc[h[:name]] = h }
    reachability_map = Statuses::Services::HostReachabilityDetector.analyze_cluster(hosts_map)

    @blocking_hosts = summary.outages.select(&:root_cause?).map(&:host)

    @outage_reports = summary.outages.map do |outage|
      host = outage.host
      reach_res = reachability_map[outage.host_name]
      {
        host: host,
        outage: outage,
        reachability: reach_res,
        impacted_services: outage.impacted_services,
        severity: outage.severity,
        root_cause: outage.root_cause?
      }
    end
  end
end
