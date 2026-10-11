# frozen_string_literal: true

class HealthController < ApplicationController
  skip_before_action :verify_authenticity_token, raise: false

  def show
    engine_connected = check_engine_connectivity
    pipe_status = check_command_pipe

    overall_healthy = engine_connected

    status_code = overall_healthy ? :ok : :service_unavailable

    render json: {
      status: overall_healthy ? "healthy" : "degraded",
      timestamp: Time.current.iso8601,
      checks: {
        app: "ok",
        nagios_engine: engine_connected ? "connected" : "unavailable",
        command_pipe: pipe_status
      },
      environment: Rails.env
    }, status: status_code
  end

  private

  def check_engine_connectivity
    program_status = Engines::NagiosEngine.program_status rescue nil
    program_status.present?
  end

  def check_command_pipe
    pipe_path = ENV.fetch('NAGIOS_CMD_PIPE', '/nagios_var/rw/nagios.cmd')
    if File.exist?(pipe_path)
      File.writable?(pipe_path) ? "ready" : "read_only"
    elsif File.directory?(File.dirname(pipe_path))
      File.writable?(File.dirname(pipe_path)) ? "directory_ready" : "directory_read_only"
    else
      "pipe_missing"
    end
  rescue StandardError
    "unknown"
  end
end
