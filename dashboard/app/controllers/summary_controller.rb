class SummaryController < ApplicationController
  def index
    @summary = Statuses::UseCases::FetchIncidentSummary.call
  end
end
