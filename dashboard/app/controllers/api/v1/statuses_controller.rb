# frozen_string_literal: true

module Api
  module V1
    class StatusesController < ApplicationController
      def index
        if !params[:query].to_s.strip.empty?
          context = {
            hosts: Engines::NagiosEngine.hosts.map(&:to_h),
            services: Engines::NagiosEngine.services.map(&:to_h),
            program_status: Engines::NagiosEngine.program_status,
            downtimes: Engines::NagiosEngine.downtimes,
            comments: Engines::NagiosEngine.comments,
            user: current_user
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
        data = Statuses::UseCases::FetchUnhandledProblems.call(filter: params[:filter])
        render json: data
      end

      def queue
        data = Statuses::UseCases::FetchSchedulingQueue.call(
          filter: params[:filter],
          sort_by: params[:sort_by] || 'next_check',
          sort_order: params[:sort_order] || :asc
        )
        render json: data
      end

      def availability
        duration = params[:duration].to_i > 0 ? params[:duration].to_i : 86_400
        data = Statuses::UseCases::FetchAvailabilityReport.call(duration_seconds: duration)
        render json: data
      end
    end
  end
end
