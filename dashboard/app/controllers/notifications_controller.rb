class NotificationsController < ApplicationController
  def index
    @notifications = Engines::NagiosEngine.notifications(duration_seconds: 86400 * 7)

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
