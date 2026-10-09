module Api
  module V1
    class StatusesController < ApplicationController
      def index
        data = Statuses::UseCases::FetchDashboardData.call
        render json: data
      end

      def tactical
        data = Statuses::UseCases::FetchTacticalOverview.call
        render json: data
      end

      def problems
        data = Statuses::UseCases::FetchUnhandledProblems.call
        render json: data
      end
    end
  end
end
