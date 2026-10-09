class PerfInfoController < ApplicationController
  def show
    services = Engines::NagiosEngine.services.map(&:to_h)

    latencies = services.map { |s| s[:latency] }
    exec_times = services.map { |s| s[:execution_time] }

    @stats = {
      total_services: services.size,
      avg_latency: latencies.any? ? (latencies.sum / latencies.size).round(3) : 0.0,
      max_latency: latencies.max || 0.0,
      avg_execution_time: exec_times.any? ? (exec_times.sum / exec_times.size).round(3) : 0.0,
      max_execution_time: exec_times.max || 0.0
    }
  end
end
