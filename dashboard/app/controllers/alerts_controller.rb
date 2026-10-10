class AlertsController < ApplicationController
  def index
    @duration = (params[:duration].presence || 86400).to_i
    @alerts = Engines::NagiosEngine.alerts(duration_seconds: @duration)
  end
end
