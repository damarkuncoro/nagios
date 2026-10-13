module Statuses
  module ValueObjects
    class StatusCode
      HOST_MAP = { 2 => 'UP', 4 => 'DOWN', 8 => 'UNREACHABLE' }.freeze
      SERVICE_MAP = { 1 => 'PENDING', 2 => 'OK', 4 => 'WARNING', 8 => 'CRITICAL', 16 => 'UNKNOWN' }.freeze

      attr_reader :value, :type

      def initialize(value, type: :service)
        @type = type
        map = type == :host ? HOST_MAP : SERVICE_MAP
        if value.is_a?(Integer)
          @value = map[value] || 'UNKNOWN'
        elsif value.to_s =~ /\A\d+\z/
          @value = map[value.to_i] || 'UNKNOWN'
        else
          @value = value.to_s.upcase
        end
      end

      def ok?
        value == 'OK' || value == 'UP'
      end

      def warning?
        value == 'WARNING'
      end

      def critical?
        value == 'CRITICAL' || value == 'DOWN'
      end

      def unknown?
        value == 'UNKNOWN' || value == 'UNREACHABLE'
      end

      def pending?
        value == 'PENDING'
      end

      def to_s
        value
      end

      def ==(other)
        value == other.to_s.upcase
      end
    end
  end
end
