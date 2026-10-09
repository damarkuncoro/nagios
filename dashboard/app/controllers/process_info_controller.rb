class ProcessInfoController < ApplicationController
  def show
    @program_status = Engines::NagiosEngine.program_status
  end

  def toggle
    feature_name = params[:feature]
    enable_flag = params[:enable] == "true"

    Engines::NagiosEngine.toggle_feature(feature_name, enable_flag)
    redirect_to process_info_path, notice: "Fitur #{feature_name.titleize} berhasil di-#{enable_flag ? 'AKTIFKAN' : 'NONAKTIFKAN'}."
  end

  def test_webhook
    webhook_url = params[:webhook_url]

    if webhook_url.present?
      success = Statuses::Services::NotificationService.send_alert(
        target_url: webhook_url,
        host_name: "production-server-01",
        service_desc: "HTTP Service",
        status: "CRITICAL",
        plugin_output: "CRITICAL - HTTP 500 Internal Server Error (Test Alert from Dashboard)"
      )

      if success
        redirect_to process_info_path, notice: "Test notifikasi Webhook berhasil dikirimkan!"
      else
        redirect_to process_info_path, alert: "Gagal mengirimkan notifikasi Webhook. Periksa URL Webhook."
      end
    else
      redirect_to process_info_path, alert: "Mohon isi URL Webhook."
    end
  end
end
