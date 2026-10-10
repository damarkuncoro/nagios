# frozen_string_literal: true

module Statuses
  module UseCases
    # Adopts event scheduling & distribution logic from base/events.c
    # Unifies Host & Service check queues and calculates check spread analytics
    class FetchSchedulingQueue
      def self.call(...)
        new(...).call
      end

      def initialize(engine: Engines::NagiosEngine, filter: nil, sort_by: 'next_check', sort_order: :asc, now: Time.now)
        @engine = engine
        @filter = filter
        @sort_by = sort_by
        @sort_order = sort_order
        @now = now
      end

      def call
        hosts = @engine.hosts rescue []
        services = @engine.services rescue []

        Services::CheckSchedulingQueue.build_queue(
          hosts: hosts,
          services: services,
          filter: @filter,
          sort_by: @sort_by,
          sort_order: @sort_order,
          now: @now
        )
      end
    end
  end
end
