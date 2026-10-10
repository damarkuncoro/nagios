module Statuses
  module Entities
    class ServiceStatus
      attr_reader :host_name, :description, :status_code, :plugin_output, :performance_data, :last_check, :next_check, :state_type, :attempts, :latency, :execution_time, :acknowledged, :notifications_enabled, :checks_enabled, :is_flapping, :flap_detection_enabled, :percent_state_change

      def initialize(host_name:, description:, status:, plugin_output: '', perf_data: '', last_check: nil, next_check: nil, state_type: 'HARD', attempts: '1/1', latency: 0.0, execution_time: 0.0, acknowledged: false, notifications_enabled: true, checks_enabled: true, is_flapping: false, flap_detection_enabled: true, percent_state_change: 0.0)
        @host_name = host_name
        @description = description
        @status_code = ValueObjects::StatusCode.new(status, type: :service)
        @plugin_output = plugin_output.to_s
        @performance_data = ValueObjects::PerformanceData.new(perf_data, description: description, plugin_output: plugin_output)
        @last_check = parse_time(last_check)
        @next_check = parse_time(next_check)
        @state_type = state_type.to_s
        @attempts = attempts.to_s
        @latency = latency.to_f
        @execution_time = execution_time.to_f
        @acknowledged = !!acknowledged
        @notifications_enabled = notifications_enabled != false
        @checks_enabled = checks_enabled != false
        @is_flapping = is_flapping == true || is_flapping.to_s == '1'
        @flap_detection_enabled = flap_detection_enabled != false
        @percent_state_change = percent_state_change.to_f
      end

      def status
        status_code.value
      end

      def ok?
        status_code.ok?
      end

      def warning?
        status_code.warning?
      end

      def critical?
        status_code.critical?
      end

      def pending?
        status_code.pending?
      end

      def acknowledged?
        @acknowledged
      end

      def flapping?
        @is_flapping
      end

      def flap_detection_enabled?
        @flap_detection_enabled
      end

      def hard_state?
        state_type == 'HARD'
      end

      def soft_state?
        state_type == 'SOFT'
      end

      def stale?(tolerance_seconds: 300)
        Services::FreshnessDetector.stale?(self, tolerance_seconds: tolerance_seconds)
      end

      def perf_data
        performance_data.raw
      end

      def dom_id
        "service_#{host_name.parameterize}_#{description.parameterize}"
      end

      def to_h
        {
          host_name: host_name,
          description: description,
          status: status,
          plugin_output: plugin_output,
          perf_data: perf_data,
          last_check: last_check,
          next_check: next_check,
          state_type: state_type,
          attempts: attempts,
          latency: latency,
          execution_time: execution_time,
          acknowledged: acknowledged,
          notifications_enabled: notifications_enabled,
          checks_enabled: checks_enabled,
          flapping: flapping?,
          flap_detection_enabled: flap_detection_enabled?,
          percent_state_change: percent_state_change,
          stale: stale?
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
