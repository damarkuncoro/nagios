module Statuses
  module Entities
    class HostStatus
      attr_reader :name, :status_code, :plugin_output, :last_check, :next_check, :current_attempt, :max_attempts, :acknowledged, :notifications_enabled, :checks_enabled, :is_flapping

      def initialize(name:, status:, plugin_output: '', last_check: nil, next_check: nil, current_attempt: 1, max_attempts: 1, acknowledged: false, notifications_enabled: true, checks_enabled: true, is_flapping: false)
        @name = name
        @status_code = ValueObjects::StatusCode.new(status, type: :host)
        @plugin_output = plugin_output.to_s
        @last_check = parse_time(last_check)
        @next_check = parse_time(next_check)
        @current_attempt = current_attempt.to_i
        @max_attempts = max_attempts.to_i
        @acknowledged = !!acknowledged
        @notifications_enabled = notifications_enabled != false
        @checks_enabled = checks_enabled != false
        @is_flapping = is_flapping == true || is_flapping.to_s == '1'
      end

      def status
        status_code.value
      end

      def up?
        status_code.ok?
      end

      def down?
        status_code.critical?
      end

      def unreachable?
        status == 'UNREACHABLE'
      end

      def acknowledged?
        @acknowledged
      end

      def flapping?
        @is_flapping
      end

      def attempts_formatted
        "#{current_attempt}/#{max_attempts}"
      end

      def stale?(tolerance_seconds: 300)
        Services::FreshnessDetector.stale?(self, tolerance_seconds: tolerance_seconds)
      end

      def to_h
        {
          name: name,
          status: status,
          plugin_output: plugin_output,
          last_check: last_check,
          next_check: next_check,
          current_attempt: current_attempt,
          max_attempts: max_attempts,
          acknowledged: acknowledged,
          notifications_enabled: notifications_enabled,
          checks_enabled: checks_enabled,
          flapping: flapping?,
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
