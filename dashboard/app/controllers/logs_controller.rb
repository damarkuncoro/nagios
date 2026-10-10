class LogsController < ApplicationController
  def index
    @filter_type = params[:type].presence || 'ALL'
    @logs = Engines::NagiosEngine.event_logs(limit: 250, filter_type: @filter_type)
  end
end
