# frozen_string_literal: true

module Statuses
  module Services
    # Adopts state flap detection algorithm from base/flapping.c
    # Implements curved percent state change analysis and hysteresis thresholds.
    class FlapDetector
      MAX_STATE_HISTORY_ENTRIES = 21
      LOW_CURVE_VALUE = 0.75
      HIGH_CURVE_VALUE = 1.25

      DEFAULT_LOW_THRESHOLD = 20.0
      DEFAULT_HIGH_THRESHOLD = 30.0

      FlapEvaluation = Struct.new(
        :flapping,
        :percent_state_change,
        :flapping_started,
        :flapping_stopped,
        :decision,
        keyword_init: true
      ) do
        def flapping?
          flapping == true
        end

        def started?
          flapping_started == true
        end

        def stopped?
          flapping_stopped == true
        end
      end

      class << self
        # Evaluates state history and determines whether object is flapping
        # based on curved changes and hysteresis thresholds (base/flapping.c)
        def evaluate(state_history,
                     current_flapping: false,
                     flap_detection_enabled: true,
                     low_threshold: DEFAULT_LOW_THRESHOLD,
                     high_threshold: DEFAULT_HIGH_THRESHOLD)
          percent_change = calculate_percent_change(state_history)

          # If flap detection is disabled globally or for target object
          unless flap_detection_enabled
            return FlapEvaluation.new(
              flapping: false,
              percent_state_change: percent_change,
              flapping_started: false,
              flapping_stopped: current_flapping,
              decision: :disabled
            )
          end

          low = low_threshold.to_f.positive? ? low_threshold.to_f : DEFAULT_LOW_THRESHOLD
          high = high_threshold.to_f.positive? ? high_threshold.to_f : DEFAULT_HIGH_THRESHOLD

          # Hysteresis calculation (base/flapping.c lines 133-154)
          if percent_change >= high
            # Above upper bound -> entering flapping state
            is_flapping = true
            started = !current_flapping
            stopped = false
            decision = :flapping
          elsif percent_change <= low
            # Below lower bound -> recovered to stable state
            is_flapping = false
            started = false
            stopped = current_flapping
            decision = :stable
          else
            # Undecided zone -> retain existing flap state
            is_flapping = current_flapping
            started = false
            stopped = false
            decision = :undecided
          end

          FlapEvaluation.new(
            flapping: is_flapping,
            percent_state_change: percent_change,
            flapping_started: started,
            flapping_stopped: stopped,
            decision: decision
          )
        end

        # Calculates weighted curved percent state change from state history array
        # Formula directly mirrors base/flapping.c lines 95-116
        def calculate_percent_change(history)
          history_arr = Array(history).compact
          return 0.0 if history_arr.size < 2

          # Take up to MAX_STATE_HISTORY_ENTRIES most recent entries
          entries = history_arr.last(MAX_STATE_HISTORY_ENTRIES)
          return 0.0 if entries.size < 2

          curved_changes = 0.0
          denominator_curve = (MAX_STATE_HISTORY_ENTRIES - 2).to_f

          (1...entries.size).each do |x|
            prev_val = entries[x - 1]
            curr_val = entries[x]

            if prev_val != curr_val
              # Curve weights more recent state transitions more heavily than older ones
              weight = (((x - 1).to_f * (HIGH_CURVE_VALUE - LOW_CURVE_VALUE)) / denominator_curve) + LOW_CURVE_VALUE
              curved_changes += weight
            end
          end

          percent = (curved_changes * 100.0) / (MAX_STATE_HISTORY_ENTRIES - 1)
          percent.round(2)
        end

        # Evaluates host or service entity and notifies broker on transitions
        def check_and_notify(target, state_history:, event_broker: Events::Broker)
          current_flapping = target.respond_to?(:flapping?) ? target.flapping? : target[:flapping]
          enabled = target.respond_to?(:flap_detection_enabled) ? target.flap_detection_enabled : true

          eval_result = evaluate(
            state_history,
            current_flapping: current_flapping == true,
            flap_detection_enabled: enabled != false
          )

          if eval_result.started?
            event_broker.publish(
              Events::Broker::FLAPPING,
              {
                action: 'started',
                target: target.respond_to?(:name) ? target.name : target[:name] || target[:description],
                percent_change: eval_result.percent_state_change
              },
              source: 'FlapDetector'
            )
          elsif eval_result.stopped?
            event_broker.publish(
              Events::Broker::FLAPPING,
              {
                action: 'stopped',
                target: target.respond_to?(:name) ? target.name : target[:name] || target[:description],
                percent_change: eval_result.percent_state_change
              },
              source: 'FlapDetector'
            )
          end

          eval_result
        end
      end
    end
  end
end
