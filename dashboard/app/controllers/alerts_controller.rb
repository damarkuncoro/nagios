class AlertsController < ApplicationController
  def index
    @alerts = Engines::NagiosEngine.alerts
  end
end
