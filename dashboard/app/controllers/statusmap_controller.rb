class StatusmapController < ApplicationController
  def index
    @map = Statuses::UseCases::FetchNetworkMap.call
  end
end
