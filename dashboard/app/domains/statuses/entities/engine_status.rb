module Statuses
  module Entities
    class EngineStatus
      attr_reader :version, :pid, :notifications_enabled, :service_checks_enabled, :passive_service_checks_enabled, :event_handlers_enabled, :flap_detection_enabled, :perf_data_enabled, :program_start

      def initialize(version: '4.x', pid: nil, notifications_enabled: true, service_checks_enabled: true, passive_service_checks_enabled: true, event_handlers_enabled: true, flap_detection_enabled: true, perf_data_enabled: true, program_start: nil)
        @version = version
        @pid = pid
        @notifications_enabled = !!notifications_enabled
        @service_checks_enabled = !!service_checks_enabled
        @passive_service_checks_enabled = !!passive_service_checks_enabled
        @event_handlers_enabled = !!event_handlers_enabled
        @flap_detection_enabled = !!flap_detection_enabled
        @perf_data_enabled = !!perf_data_enabled
        @program_start = parse_time(program_start)
      end

      def to_h
        {
          version: version,
          pid: pid,
          notifications_enabled: notifications_enabled,
          service_checks_enabled: service_checks_enabled,
          passive_service_checks_enabled: passive_service_checks_enabled,
          event_handlers_enabled: event_handlers_enabled,
          flap_detection_enabled: flap_detection_enabled,
          perf_data_enabled: perf_data_enabled,
          program_start: program_start
        }
      end

      private

      def parse_time(value)
        return nil if value.nil? || value.to_i <= 0
        value.is_a?(Time) ? value : Time.at(value.to_i > 1_000_000_000_000 ? value.to_i / 1000 : value.to_i)
      end
    end
  end
end
