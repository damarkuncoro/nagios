class HostsController < ApplicationController
  def index
    data = Statuses::UseCases::FetchDashboardData.call

    @program_status = data[:program_status]
    @hosts = data[:hosts]
    @services = data[:services]
    @host_stats = data[:host_stats]
    @service_stats = data[:service_stats]
  end

  def show
    host_name = params[:id]
    hosts = Engines::NagiosEngine.hosts.map(&:to_h)
    @host = hosts.find { |h| h[:name] == host_name } || { name: host_name, status: 'UP', plugin_output: 'Host active' }

    all_services = Engines::NagiosEngine.services.map(&:to_h)
    @services = all_services.select { |s| s[:host_name] == host_name }

    all_comments = Engines::NagiosEngine.comments
    @comments = all_comments.select { |c| c[:host_name] == host_name }

    all_downtimes = Engines::NagiosEngine.downtimes
    @downtimes = all_downtimes.select { |d| d[:host_name] == host_name }
  end

  def recheck
    host_name = params[:id]
    Statuses::UseCases::ScheduleCheck.host(host_name)

    @hosts = Engines::NagiosEngine.hosts.map(&:to_h)
    @host = @hosts.find { |h| h[:name] == host_name } || { name: host_name, status: 'PENDING', plugin_output: 'Re-check scheduled...', last_check: Time.now }

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "host_#{host_name.parameterize}",
          partial: "hosts/host_row",
          locals: { host: @host }
        )
      end
      format.html { redirect_to hosts_path, notice: "Re-check host #{host_name} dijadwalkan!" }
    end
  end

  def recheck_service
    host_name = params[:id]
    service_desc = params[:service_desc]

    Statuses::UseCases::ScheduleCheck.service(host_name, service_desc)

    @services = Engines::NagiosEngine.services.map(&:to_h)
    @service = @services.find { |s| s[:host_name] == host_name && s[:description] == service_desc } || {
      host_name: host_name, description: service_desc, status: 'PENDING', plugin_output: 'Re-check scheduled...', last_check: Time.now
    }

    dom_id = "service_#{host_name.parameterize}_#{service_desc.parameterize}"

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          dom_id,
          partial: "hosts/service_row",
          locals: { service: @service }
        )
      end
      format.html { redirect_to hosts_path, notice: "Re-check service #{service_desc} dijadwalkan!" }
    end
  end

  def acknowledge_service
    host_name = params[:id]
    service_desc = params[:service_desc]
    comment = params[:comment].presence || "Acknowledged via Rails Dashboard"

    Statuses::UseCases::AcknowledgeProblem.service(host_name, service_desc, comment: comment)

    @services = Engines::NagiosEngine.services.map(&:to_h)
    @service = @services.find { |s| s[:host_name] == host_name && s[:description] == service_desc } || {
      host_name: host_name, description: service_desc, status: 'WARNING', plugin_output: 'Acknowledged...', last_check: Time.now, acknowledged: true
    }

    dom_id = "service_#{host_name.parameterize}_#{service_desc.parameterize}"

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          dom_id,
          partial: "hosts/service_row",
          locals: { service: @service }
        )
      end
      format.html { redirect_to hosts_path, notice: "Problem service #{service_desc} telah di-Acknowledge!" }
    end
  end

  def schedule_service_downtime
    host_name = params[:id]
    service_desc = params[:service_desc]
    duration_hours = (params[:duration_hours].presence || 1).to_i

    Statuses::UseCases::ScheduleDowntime.service(host_name, service_desc, duration_hours: duration_hours)

    redirect_to downtimes_path, notice: "Downtime #{duration_hours} jam untuk #{service_desc} di #{host_name} berhasil dijadwalkan!"
  end
end
