class PerfInfoController < ApplicationController
  def show
    hosts = (Engines::NagiosEngine.hosts rescue []).map(&:to_h)
    services = (Engines::NagiosEngine.services rescue []).map(&:to_h)

    summary = Statuses::Services::OperationalMetricsAggregator.aggregate(hosts: hosts, services: services)

    @parsed_metrics = services.map do |s|
      perf_raw = s[:performance_data] || s['perf_data'] || s['performance_data']
      next if perf_raw.blank?

      parsed = Statuses::Services::PerfdataParser.parse("#{s[:plugin_output]} | #{perf_raw}")
      next unless parsed.has_metrics?

      {
        host_name: s[:host_name],
        description: s[:description],
        status: s[:status],
        metrics: parsed.metrics
      }
    end.compact

    @stats = {
      total_services: summary.services[:total],
      total_hosts: summary.hosts[:total],
      avg_latency: summary.latency[:avg],
      max_latency: summary.latency[:max],
      min_latency: summary.latency[:min],
      avg_execution_time: summary.execution_time[:avg],
      max_execution_time: summary.execution_time[:max],
      min_execution_time: summary.execution_time[:min],
      health_percentage: summary.health_percentage,
      summary: summary
    }
  end
end
