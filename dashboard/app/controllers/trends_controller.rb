class TrendsController < ApplicationController
  def index
    @trends = Statuses::UseCases::FetchTrendsMetrics.call(days: 7)
  end
end
