class QueueController < ApplicationController
  def index
    result = Statuses::UseCases::FetchSchedulingQueue.call(filter: params[:filter])
    @queue = result[:items]
    @metrics = result[:metrics]
    @filter = params[:filter]
  end
end
