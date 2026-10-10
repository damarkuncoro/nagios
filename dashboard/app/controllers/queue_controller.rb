# frozen_string_literal: true

class QueueController < ApplicationController
  def index
    @filter = params[:filter]
    @sort_by = params[:sort_by] || 'next_check'
    @sort_order = params[:sort_order] || :asc

    result = Statuses::UseCases::FetchSchedulingQueue.call(
      filter: @filter,
      sort_by: @sort_by,
      sort_order: @sort_order
    )
    @queue = result[:items]
    @metrics = result[:metrics]
  end
end
