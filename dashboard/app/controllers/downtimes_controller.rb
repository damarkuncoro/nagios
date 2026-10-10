class DowntimesController < ApplicationController
  def index
    @downtimes = Engines::NagiosEngine.downtimes
  end

  def destroy
    downtime_id = params[:id]
    Engines::NagiosEngine.cancel_downtime(downtime_id)
    Statuses::Services::DowntimeCoordinator.cancel_downtime(downtime_id)
    redirect_to downtimes_path, notice: "Downtime ##{downtime_id} berhasil dibatalkan."
  end
end
