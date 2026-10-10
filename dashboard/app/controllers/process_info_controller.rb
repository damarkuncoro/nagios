class ProcessInfoController < ApplicationController
  def show
    @program_status = (Engines::NagiosEngine.program_status rescue nil) || default_program_status
    @recent_broker_events = Statuses::Events::Broker.history(limit: 5)
    @daemon_status = Statuses::Services::DaemonLifecycleCoordinator.status
    @neb_modules = Statuses::Services::NebModuleRegistry.modules
    @radio_stats = Statuses::Services::EventRadioDispatcher.stats
    @qh_ping = Statuses::Services::QueryHandlerClient.ping
  end

  def toggle
    feature_name = params[:feature]
    enable_flag = params[:enable] == "true"

    Engines::NagiosEngine.toggle_feature(feature_name, enable_flag)
    redirect_to process_info_path, notice: "Fitur #{feature_name.titleize} berhasil di-#{enable_flag ? 'AKTIFKAN' : 'NONAKTIFKAN'}."
  end

  def toggle_daemon
    action = params[:daemon_action].to_s

    case action
    when 'start'
      Statuses::Services::DaemonLifecycleCoordinator.start!
      msg = "Daemon Coordinator berhasil DIMULAI (Running)."
    when 'pause'
      Statuses::Services::DaemonLifecycleCoordinator.pause!
      msg = "Daemon Coordinator berhasil DIJEDA (Paused)."
    when 'resume'
      Statuses::Services::DaemonLifecycleCoordinator.resume!
      msg = "Daemon Coordinator berhasil DILANJUTKAN (Running)."
    when 'stop'
      Statuses::Services::DaemonLifecycleCoordinator.stop!
      msg = "Daemon Coordinator berhasil DIHENTIKAN (Stopped)."
    else
      msg = "Aksi daemon tidak dikenal."
    end

    redirect_to process_info_path, notice: msg
  end

  def test_tcp_probe
    host = params[:host].presence || '127.0.0.1'
    port = params[:port].presence || 80
    timeout = params[:timeout].presence&.to_f || 2.0

    res = Statuses::Services::NetUtils.tcp_connect(host, port, timeout: timeout)
    if res.success?
      notice_msg = "TCP Probe BERHASIL: Port #{port} pada #{host} terbuka (Latensi: #{res.latency_ms} ms)."
      redirect_to process_info_path, notice: notice_msg
    else
      alert_msg = "TCP Probe GAGAL: Port #{port} pada #{host} tidak dapat dijangkau (#{res.error})."
      redirect_to process_info_path, alert: alert_msg
    end
  end

  def execute_command
    raw_cmd = params[:command_string].to_s.strip
    if raw_cmd.present?
      result = Statuses::Services::DaemonLifecycleCoordinator.process_command(raw_cmd)
      if result.success?
        redirect_to process_info_path, notice: "Perintah Nagios berhasil dieksekusi: #{result.message}"
      else
        redirect_to process_info_path, alert: "Perintah Nagios gagal: #{result.message}"
      end
    else
      redirect_to process_info_path, alert: "String perintah eksternal tidak boleh kosong."
    end
  end

  def test_webhook
    webhook_url = params[:webhook_url]

    if webhook_url.present?
      result = Statuses::Services::NotificationService.deliver_alert(
        target_url: webhook_url,
        host_name: "production-server-01",
        service_desc: "HTTP Service",
        status: "CRITICAL",
        plugin_output: "CRITICAL - HTTP 500 Internal Server Error (Test Alert from Dashboard)"
      )

      if result.success?
        redirect_to process_info_path, notice: "Test notifikasi Webhook (#{result.platform.to_s.upcase}) berhasil dikirimkan!"
      else
        redirect_to process_info_path, alert: "Gagal mengirimkan notifikasi Webhook (#{result.platform.to_s.upcase}): #{result.error}"
      end
    else
      redirect_to process_info_path, alert: "Mohon isi URL Webhook."
    end
  end

  private

  def default_program_status
    {
      version: '4.4.6',
      pid: Process.pid,
      program_start: Time.current - 1.day,
      notifications_enabled: true,
      service_checks_enabled: true,
      flap_detection_enabled: true,
      event_handlers_enabled: true
    }
  end
end
