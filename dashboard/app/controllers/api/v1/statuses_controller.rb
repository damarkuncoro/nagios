module Api
  module V1
    class StatusesController < ApplicationController
      def index
        if params[:query].present?
          context = {
            hosts: Engines::NagiosEngine.hosts.map(&:to_h),
            services: Engines::NagiosEngine.services.map(&:to_h),
            program_status: Engines::NagiosEngine.program_status,
            downtimes: Engines::NagiosEngine.downtimes,
            comments: Engines::NagiosEngine.comments,
            user: 'nagiosadmin'
          }
          response_json = Statuses::Services::StatusJsonSerializer.serialize_query(
            params[:query],
            params.to_unsafe_h,
            context
          )
          render json: response_json
        else
          data = Statuses::UseCases::FetchDashboardData.call
          render json: data
        end
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
