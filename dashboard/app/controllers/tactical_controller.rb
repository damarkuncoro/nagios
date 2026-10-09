class TacticalController < ApplicationController
  def index
    @tac = Statuses::UseCases::FetchTacticalOverview.call
  end
end
