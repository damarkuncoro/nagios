module Statuses
  module Events
    class Event
      attr_reader :type, :payload, :source, :timestamp

      def initialize(type:, payload: {}, source: 'system', timestamp: Time.now)
        @type = type.to_sym
        @payload = payload.is_a?(Hash) ? payload : {}
        @source = source.to_s
        @timestamp = timestamp
      end

      def to_h
        {
          type: type,
          payload: payload,
          source: source,
          timestamp: timestamp
        }
      end
    end
  end
end
