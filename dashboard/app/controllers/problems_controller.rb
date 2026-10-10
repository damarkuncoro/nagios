class ProblemsController < ApplicationController
  def index
    @filter = params[:filter]
    @problems = Statuses::UseCases::FetchUnhandledProblems.call(filter: @filter)
  end
end
