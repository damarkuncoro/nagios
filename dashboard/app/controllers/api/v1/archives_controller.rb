# frozen_string_literal: true

module Api
  module V1
    class ArchivesController < ApplicationController
      def index
        query_name = params[:query] || 'alertlist'
        
        # Load event logs from NagiosEngine or empty array fallback
        entries = begin
          Engines::NagiosEngine.event_logs
        rescue StandardError
          []
        end

        context = {
          log_entries: entries,
          hosts: Engines::NagiosEngine.hosts.map(&:to_h),
          services: Engines::NagiosEngine.services.map(&:to_h),
          program_status: Engines::NagiosEngine.program_status.to_h,
          user: current_user
        }

        response_json = Statuses::Services::ArchiveJsonSerializer.serialize_query(
          query_name,
          params.to_unsafe_h,
          context
        )

        render json: response_json
      end
    end
  end
end
