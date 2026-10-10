# frozen_string_literal: true

module Statuses
  module Services
    # Adopts Nagios Event Radio Dispatcher (NERD) from base/nerd.c
    # Implements channel-based pub/sub streaming dispatcher for reactive monitoring subscriptions.
    class EventRadioDispatcher
      CHANNELS = %i[
        host_checks
        service_checks
        state_changes
        flapping
        downtimes
        alerts
      ].freeze

      MAX_CHANNEL_HISTORY = 50

      class << self
        def instance
          @instance ||= new
        end

        def subscribe(channel, &block)
          instance.subscribe(channel, &block)
        end

        def unsubscribe(channel, subscription_id)
          instance.unsubscribe(channel, subscription_id)
        end

        def broadcast(channel, payload = {})
          instance.broadcast(channel, payload)
        end

        def channel_history(channel, limit: 20)
          instance.channel_history(channel, limit: limit)
        end

        def stats
          instance.stats
        end

        def clear!
          instance.clear!
        end
      end

      def initialize
        @channels = Hash.new { |h, k| h[k] = {} }
        @channel_histories = Hash.new { |h, k| h[k] = [] }
        @mutex = Mutex.new
        @sub_counter = 1
      end

      # Subscribes a listener block to a specific channel
      def subscribe(channel, &block)
        return nil unless block_given?

        ch_sym = channel.to_sym
        @mutex.synchronize do
          sub_id = @sub_counter
          @sub_counter += 1
          @channels[ch_sym][sub_id] = block
          sub_id
        end
      end

      # Unsubscribes a listener by subscription_id
      def unsubscribe(channel, subscription_id)
        ch_sym = channel.to_sym
        @mutex.synchronize do
          @channels[ch_sym].delete(subscription_id)
        end
      end

      # Broadcasts a payload message to all subscribers of a channel
      def broadcast(channel, payload = {})
        ch_sym = channel.to_sym
        message = {
          channel: ch_sym,
          timestamp: (Time.respond_to?(:current) ? Time.current : Time.now).to_i,
          payload: payload
        }

        subscribers = []
        @mutex.synchronize do
          history = @channel_histories[ch_sym]
          history.unshift(message)
          history.pop if history.size > MAX_CHANNEL_HISTORY

          subscribers = @channels[ch_sym].values
        end

        subscribers.each do |sub|
          sub.call(message)
        rescue StandardError => e
          Rails.logger.error("[NERD] Gagal mengirim pesan ke subscriber channel #{ch_sym}: #{e.message}")
        end

        message
      end

      # Retrieves recent message backlog for a channel
      def channel_history(channel, limit: 20)
        ch_sym = channel.to_sym
        @mutex.synchronize do
          @channel_histories[ch_sym].first(limit)
        end
      end

      # Returns dispatcher channel statistics
      def stats
        @mutex.synchronize do
          {
            active_channels: @channels.keys,
            subscriber_counts: @channels.transform_values(&:size),
            total_subscribers: @channels.values.sum(&:size)
          }
        end
      end

      def clear!
        @mutex.synchronize do
          @channels.clear
          @channel_histories.clear
        end
      end
    end
  end
end
