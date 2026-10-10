# frozen_string_literal: true

class PerfInfoController < ApplicationController
  def show
    hosts = begin
      Engines::NagiosEngine.hosts.map(&:to_h)
    rescue StandardError
      []
    end

    services = begin
      Engines::NagiosEngine.services.map(&:to_h)
    rescue StandardError
      []
    end

    respond_to do |format|
      format.html do
        summary = Statuses::Services::OperationalMetricsAggregator.aggregate(hosts: hosts, services: services)

        @parsed_metrics = services.map do |s|
          perf_raw = s[:performance_data] || s['perf_data'] || s['performance_data']
          next if perf_raw.nil? || perf_raw.to_s.strip.empty?

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

      format.text do
        prom_data = Statuses::Services::PerformanceDataProcessor.to_prometheus(hosts: hosts, services: services)
        render plain: prom_data, content_type: 'text/plain; version=0.0.4; charset=utf-8'
      end
    end
  end

  def metrics
    hosts = begin
      Engines::NagiosEngine.hosts.map(&:to_h)
    rescue StandardError
      []
    end

    services = begin
      Engines::NagiosEngine.services.map(&:to_h)
    rescue StandardError
      []
    end

    prom_data = Statuses::Services::PerformanceDataProcessor.to_prometheus(hosts: hosts, services: services)
    render plain: prom_data, content_type: 'text/plain; version=0.0.4; charset=utf-8'
  end
end
