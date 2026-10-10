# frozen_string_literal: true

class NotificationsController < ApplicationController
  def index
    raw = begin
      Engines::NagiosEngine.notifications(duration_seconds: 86400 * 7)
    rescue StandardError
      []
    end

    @stats = Statuses::Services::NotificationHistoryManager.calculate_stats(raw)

    has_filter = !params[:contact].to_s.strip.empty? || !params[:host].to_s.strip.empty? || !params[:reason].to_s.strip.empty?

    @notifications = if has_filter
      Statuses::Services::NotificationHistoryManager.filter(
        raw,
        contact_name: params[:contact],
        host_name: params[:host],
        reason: params[:reason]
      )
    else
      raw
    end

    respond_to do |format|
      format.html
      format.csv do
        send_data Statuses::UseCases::ExportNotificationsCsv.call(@notifications),
                  filename: "nagios-notifications-#{Date.today}.csv",
                  type: 'text/csv; charset=utf-8'
      end
    end
  end
end
