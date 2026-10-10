# frozen_string_literal: true

module Api
  module V1
    class ObjectsController < ApplicationController
      def index
        query_name = params[:query] || 'hostlist'
        servicegroups = begin
          Engines::NagiosEngine.servicegroups
        rescue StandardError
          []
        end

        context = {
          hosts: Engines::NagiosEngine.hosts.map(&:to_h),
          services: Engines::NagiosEngine.services.map(&:to_h),
          hostgroups: Engines::NagiosEngine.hostgroups,
          servicegroups: servicegroups,
          contacts: Engines::NagiosEngine.contacts,
          contactgroups: Engines::NagiosEngine.contactgroups,
          timeperiods: Engines::NagiosEngine.timeperiods,
          commands: Engines::NagiosEngine.commands,
          user: 'nagiosadmin'
        }

        response_json = Statuses::Services::ObjectJsonSerializer.serialize_query(
          query_name,
          params.to_unsafe_h,
          context
        )

        render json: response_json
      end
    end
  end
end
