class HostsController < ApplicationController
  def index
    data = Statuses::UseCases::FetchDashboardData.call(
      search: params[:search],
      status: params[:status],
      sort_by: params[:sort_by],
      sort_order: params[:sort_order] || :asc
    )

    @program_status = data[:program_status]
    @hosts = data[:hosts]
    @services = data[:services]
    @host_stats = data[:host_stats]
    @service_stats = data[:service_stats]
    @host_totals = data[:host_totals]
    @service_totals = data[:service_totals]
    @search = params[:search]
    @status = params[:status]
    @sort_by = params[:sort_by]
    @sort_order = params[:sort_order]

    respond_to do |format|
      format.html
      format.csv do
        send_data Statuses::UseCases::ExportHostsCsv.call(@hosts),
                  filename: "nagios-hosts-#{Date.today}.csv",
                  type: 'text/csv; charset=utf-8'
      end
    end
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
    respond_host_update(host_name, status: 'PENDING', output: 'Re-check scheduled...', notice: "Re-check host #{host_name} dijadwalkan!")
  end

  def recheck_service
    host_name = params[:id]
    service_desc = params[:service_desc]
    Statuses::UseCases::ScheduleCheck.service(host_name, service_desc)
    respond_service_update(host_name, service_desc, status: 'PENDING', output: 'Re-check scheduled...', notice: "Re-check service #{service_desc} dijadwalkan!")
  end

  def recheck_all_services
    host_name = params[:id]
    Engines::NagiosEngine.schedule_forced_host_svc_checks(host_name)
    redirect_back fallback_location: host_path(host_name),
                  notice: "Seluruh pemeriksaan service di host #{host_name} berhasil dijadwalkan ulang secara serentak!"
  end

  def acknowledge
    host_name = params[:id]
    comment = params[:comment].presence || "Acknowledged via Rails Dashboard"
    Statuses::UseCases::AcknowledgeProblem.host(host_name, comment: comment)
    respond_host_update(host_name, status: 'DOWN', output: 'Acknowledged...', acknowledged: true, notice: "Problem host #{host_name} telah di-Acknowledge!")
  end

  def remove_acknowledgment
    host_name = params[:id]
    Statuses::UseCases::RemoveAcknowledgment.host(host_name)
    respond_host_update(host_name, status: 'DOWN', output: 'ACK removed...', acknowledged: false, notice: "Acknowledgment untuk host #{host_name} telah dicabut (Disack)!")
  end

  def acknowledge_service
    host_name = params[:id]
    service_desc = params[:service_desc]
    comment = params[:comment].presence || "Acknowledged via Rails Dashboard"
    Statuses::UseCases::AcknowledgeProblem.service(host_name, service_desc, comment: comment)
    respond_service_update(host_name, service_desc, status: 'WARNING', output: 'Acknowledged...', acknowledged: true, notice: "Problem service #{service_desc} telah di-Acknowledge!")
  end

  def remove_service_acknowledgment
    host_name = params[:id]
    service_desc = params[:service_desc]
    Statuses::UseCases::RemoveAcknowledgment.service(host_name, service_desc)
    respond_service_update(host_name, service_desc, status: 'CRITICAL', output: 'ACK removed...', acknowledged: false, notice: "Acknowledgment untuk service #{service_desc} telah dicabut (Disack)!")
  end

  def schedule_downtime
    host_name = params[:id]
    duration_hours = params[:duration_hours] || 2
    author = params[:author].presence || 'nagiosadmin'
    comment = params[:comment].presence || "Scheduled Maintenance via Dashboard (#{duration_hours} jam)"
    Statuses::UseCases::ScheduleDowntime.host(host_name, duration_hours: duration_hours, author: author, comment: comment)
    redirect_to downtimes_path, notice: "Downtime host #{host_name} (#{duration_hours} jam) berhasil dijadwalkan!"
  end

  def schedule_cluster_downtime
    host_name = params[:id]
    duration_hours = params[:duration_hours] || 2
    author = params[:author].presence || 'nagiosadmin'
    comment = params[:comment].presence || "Scheduled Cluster Maintenance via Dashboard (#{duration_hours} jam)"
    Statuses::UseCases::ScheduleDowntime.cluster(host_name, duration_hours: duration_hours, author: author, comment: comment)
    redirect_to downtimes_path, notice: "Downtime serentak untuk Host #{host_name} dan seluruh Services (#{duration_hours} jam) berhasil dijadwalkan!"
  end

  def schedule_service_downtime
    host_name = params[:id]
    service_desc = params[:service_desc]
    duration_hours = params[:duration_hours] || 2
    author = params[:author].presence || 'nagiosadmin'
    comment = params[:comment].presence || "Scheduled Maintenance via Dashboard (#{duration_hours} jam)"
    Statuses::UseCases::ScheduleDowntime.service(host_name, service_desc, duration_hours: duration_hours, author: author, comment: comment)
    redirect_to downtimes_path, notice: "Downtime service #{service_desc} pada #{host_name} (#{duration_hours} jam) berhasil dijadwalkan!"
  end

  def toggle_notifications
    host_name = params[:id]
    enable_flag = params[:enable] == 'true'
    Engines::NagiosEngine.toggle_host_notifications(host_name, enable_flag)
    respond_host_update(host_name, notifications_enabled: enable_flag, notice: "Notifikasi host #{host_name} berhasil di-#{enable_flag ? 'AKTIFKAN' : 'NONAKTIFKAN'}!")
  end

  def toggle_service_notifications
    host_name = params[:id]
    service_desc = params[:service_desc]
    enable_flag = params[:enable] == 'true'
    Engines::NagiosEngine.toggle_service_notifications(host_name, service_desc, enable_flag)
    respond_service_update(host_name, service_desc, notifications_enabled: enable_flag, notice: "Notifikasi service #{service_desc} di #{host_name} berhasil di-#{enable_flag ? 'AKTIFKAN' : 'NONAKTIFKAN'}!")
  end

  def toggle_checks
    host_name = params[:id]
    enable_flag = params[:enable] == 'true'
    Engines::NagiosEngine.toggle_host_checks(host_name, enable_flag)
    respond_host_update(host_name, checks_enabled: enable_flag, notice: "Active check host #{host_name} berhasil di-#{enable_flag ? 'AKTIFKAN' : 'NONAKTIFKAN'}!")
  end

  def toggle_service_checks
    host_name = params[:id]
    service_desc = params[:service_desc]
    enable_flag = params[:enable] == 'true'
    Engines::NagiosEngine.toggle_service_checks(host_name, service_desc, enable_flag)
    respond_service_update(host_name, service_desc, checks_enabled: enable_flag, notice: "Active check service #{service_desc} di #{host_name} berhasil di-#{enable_flag ? 'AKTIFKAN' : 'NONAKTIFKAN'}!")
  end

  def toggle_flap_detection
    host_name = params[:id]
    enable_flag = params[:enable] == 'true'
    Engines::NagiosEngine.toggle_host_flap_detection(host_name, enable_flag)
    respond_host_update(host_name, flap_detection_enabled: enable_flag, notice: "Flap detection host #{host_name} berhasil di-#{enable_flag ? 'AKTIFKAN' : 'NONAKTIFKAN'}!")
  end

  def toggle_service_flap_detection
    host_name = params[:id]
    service_desc = params[:service_desc]
    enable_flag = params[:enable] == 'true'
    Engines::NagiosEngine.toggle_service_flap_detection(host_name, service_desc, enable_flag)
    respond_service_update(host_name, service_desc, flap_detection_enabled: enable_flag, notice: "Flap detection service #{service_desc} di #{host_name} berhasil di-#{enable_flag ? 'AKTIFKAN' : 'NONAKTIFKAN'}!")
  end

  def submit_passive_check
    host_name = params[:id]
    service_desc = params[:service_desc]
    status_code = params[:status_code].to_i
    output = params[:output].presence || "Manual check submission via Modern Rails Dashboard"
    Engines::NagiosEngine.submit_passive_check(host_name, service_desc, status_code, output)
    redirect_back fallback_location: host_path(host_name),
                  notice: "Hasil passive check [Code: #{status_code}] untuk #{service_desc || host_name} berhasil dikirim ke Nagios Engine!"
  end

  private

  def respond_host_update(host_name, status: nil, output: nil, acknowledged: nil, notifications_enabled: nil, checks_enabled: nil, flap_detection_enabled: nil, notice: nil)
    @hosts = Engines::NagiosEngine.hosts.map(&:to_h)
    @host = @hosts.find { |h| h[:name] == host_name } || { name: host_name, status: status || 'UP', plugin_output: output || 'Updated', last_check: Time.now }
    @host[:acknowledged] = acknowledged unless acknowledged.nil?
    @host[:notifications_enabled] = notifications_enabled unless notifications_enabled.nil?
    @host[:checks_enabled] = checks_enabled unless checks_enabled.nil?
    @host[:flap_detection_enabled] = flap_detection_enabled unless flap_detection_enabled.nil?

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("host_#{host_name.parameterize}", partial: "hosts/host_row", locals: { host: @host })
      end
      format.html { redirect_back fallback_location: host_path(host_name), notice: notice }
    end
  end

  def respond_service_update(host_name, service_desc, status: nil, output: nil, acknowledged: nil, notifications_enabled: nil, checks_enabled: nil, flap_detection_enabled: nil, notice: nil)
    @services = Engines::NagiosEngine.services.map(&:to_h)
    @service = @services.find { |s| s[:host_name] == host_name && s[:description] == service_desc } || {
      host_name: host_name, description: service_desc, status: status || 'OK', plugin_output: output || 'Updated', last_check: Time.now
    }
    @service[:acknowledged] = acknowledged unless acknowledged.nil?
    @service[:notifications_enabled] = notifications_enabled unless notifications_enabled.nil?
    @service[:checks_enabled] = checks_enabled unless checks_enabled.nil?
    @service[:flap_detection_enabled] = flap_detection_enabled unless flap_detection_enabled.nil?
    dom_id = "service_#{host_name.parameterize}_#{service_desc.parameterize}"

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(dom_id, partial: "hosts/service_row", locals: { service: @service })
      end
      format.html { redirect_back fallback_location: host_path(host_name), notice: notice }
    end
  end
end
