module Statuses
  module Events
    class Broker
      ACKNOWLEDGEMENT = :acknowledgement
      DOWNTIME        = :downtime
      CHECK           = :check
      PASSIVE_CHECK   = :passive_check
      COMMENT         = :comment
      STATE_CHANGE    = :state_change

      MAX_HISTORY = 100

      class << self
        def instance
          @instance ||= new
        end

        def register_callback(event_type, &block)
          instance.register_callback(event_type, &block)
        end

        def publish(event_type, payload = {}, source: 'system')
          instance.publish(event_type, payload, source: source)
        end

        def history(limit: 50)
          instance.history(limit: limit)
        end

        def clear_callbacks!
          instance.clear_callbacks!
        end

        def clear_history!
          instance.clear_history!
        end
      end

      def initialize
        @callbacks = Hash.new { |hash, key| hash[key] = [] }
        @history = []
        @mutex = Mutex.new
      end

      def register_callback(event_type, &block)
        return unless block_given?

        @mutex.synchronize do
          @callbacks[event_type.to_sym] << block
        end
      end

      def publish(event_type, payload = {}, source: 'system')
        event = Event.new(type: event_type, payload: payload, source: source)

        @mutex.synchronize do
          @history.unshift(event)
          @history.pop if @history.size > MAX_HISTORY
        end

        subscribers = @mutex.synchronize { @callbacks[event.type].dup + @callbacks[:all].dup }

        subscribers.each do |subscriber|
          subscriber.call(event)
        rescue StandardError => e
          Rails.logger.error("[Broker] Gagal mengeksekusi callback untuk #{event_type}: #{e.message}")
        end

        event
      end

      def history(limit: 50)
        @mutex.synchronize do
          @history.first(limit).map(&:to_h)
        end
      end

      def clear_callbacks!
        @mutex.synchronize { @callbacks.clear }
      end

      def clear_history!
        @mutex.synchronize { @history.clear }
      end
    end
  end
end
