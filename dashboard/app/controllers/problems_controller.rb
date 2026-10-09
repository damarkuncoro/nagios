class ProblemsController < ApplicationController
  def index
    @problems = Statuses::UseCases::FetchUnhandledProblems.call
  end
end
