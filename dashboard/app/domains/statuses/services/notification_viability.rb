# frozen_string_literal: true

module Statuses
  module Services
    # Adopts notification viability checks from base/notifications.c
    # Implements check_service_notification_viability and check_host_notification_viability
    class NotificationViability
      TYPES = {
        normal: :normal,
        acknowledgement: :acknowledgement,
        flapping_start: :flapping_start,
        flapping_stop: :flapping_stop,
        flapping_disabled: :flapping_disabled,
        downtime_start: :downtime_start,
        downtime_end: :downtime_end,
        custom: :custom,
        recovery: :recovery
      }.freeze

      ViabilityResult = Struct.new(
        :viable,
        :reason,
        :code,
        keyword_init: true
      ) do
        def viable?
          viable == true
        end
      end

      class << self
        def check(target,
                  type: :normal,
                  host: nil,
                  parent_states: [],
                  options: {},
                  global_notifications_enabled: true,
                  current_time: (Time.respond_to?(:current) ? Time.current : Time.now))
          type = type.to_sym

          # 1. Forced option overrides all filters (base/notifications.c line 359)
          if options[:forced] == true
            return ViabilityResult.new(
              viable: true,
              reason: 'Notification is forced, overriding all standard filters',
              code: :forced_override
            )
          end

          # 2. Check global notifications setting (line 369)
          unless global_notifications_enabled
            return ViabilityResult.new(
              viable: false,
              reason: 'Global notifications are currently disabled in monitoring engine',
              code: :global_notifications_disabled
            )
          end

          # 3. Check target object notifications enabled (line 431)
          target_notifications_enabled = target_attr(target, :notifications_enabled, default: true)
          unless target_notifications_enabled
            return ViabilityResult.new(
              viable: false,
              reason: 'Notifications are disabled for this object',
              code: :object_notifications_disabled
            )
          end

          # 4. Check Parent dependencies / network reachability (line 385)
          if parent_states.present?
            # If all parent objects are failed/down, suppress child alerts
            all_parents_failed = parent_states.all? do |st|
              st.to_s.upcase.in?(%w[CRITICAL DOWN UNREACHABLE 1 2])
            end
            if all_parents_failed
              return ViabilityResult.new(
                viable: false,
                reason: 'All parent dependencies are in failed state (notification suppressed)',
                code: :parent_failure_suppression
              )
            end
          end

          # 5. Scheduled downtime suppression (lines 443, 484, 508)
          target_downtime = target_attr(target, :scheduled_downtime_depth, default: 0).to_i
          host_downtime = host ? target_attr(host, :scheduled_downtime_depth, default: 0).to_i : 0
          in_downtime = target_downtime.positive? || host_downtime.positive?

          if in_downtime && type.in?(%i[normal custom flapping_start flapping_stop])
            return ViabilityResult.new(
              viable: false,
              reason: 'Object or host is currently within scheduled downtime',
              code: :in_scheduled_downtime
            )
          end

          # 6. Acknowledgement alerts specific rules (line 457)
          if type == :acknowledgement
            curr_state = target_attr(target, :status, default: 0)
            if curr_state.to_s.upcase.in?(%w[OK UP 0])
              return ViabilityResult.new(
                viable: false,
                reason: 'Cannot send acknowledgement notification when state is OK/UP',
                code: :no_problem_for_ack
              )
            end
            return ViabilityResult.new(
              viable: true,
              reason: 'Acknowledgement notification is viable',
              code: :ok
            )
          end

          # 7. Flapping notification filtering (line 475)
          if type.in?(%i[flapping_start flapping_stop flapping_disabled])
            flap_notif_enabled = target_attr(target, :flap_notifications_enabled, default: true)
            unless flap_notif_enabled
              return ViabilityResult.new(
                viable: false,
                reason: 'Flapping notifications are disabled for this object',
                code: :flapping_notifications_disabled
              )
            end
            return ViabilityResult.new(
              viable: true,
              reason: 'Flapping notification is viable',
              code: :ok
            )
          end

          # 8. Notification interval throttling (base/notifications.c line 600+)
          interval_minutes = target_attr(target, :notification_interval, default: 0).to_f
          last_notification_time = target_attr(target, :last_notification, default: nil)
          notification_count = target_attr(target, :current_notification_number, default: 0).to_i

          if notification_count.positive? && interval_minutes.positive? && last_notification_time.present?
            last_time = last_notification_time.is_a?(Time) ? last_notification_time : Time.zone.parse(last_notification_time.to_s) rescue nil
            if last_time && (current_time < (last_time + (interval_minutes * 60)))
              return ViabilityResult.new(
                viable: false,
                reason: "Notification suppressed: interval throttle active until #{last_time + (interval_minutes * 60)}",
                code: :throttled_by_interval
              )
            end
          end

          # Passed all top-level viability filters
          ViabilityResult.new(
            viable: true,
            reason: 'Notification viability test passed',
            code: :ok
          )
        end

        private

        def target_attr(target, attr_name, default: nil)
          return default if target.nil?

          if target.respond_to?(attr_name)
            val = target.public_send(attr_name)
            val.nil? ? default : val
          elsif target.is_a?(Hash)
            if target.key?(attr_name.to_s)
              target[attr_name.to_s]
            elsif target.key?(attr_name.to_sym)
              target[attr_name.to_sym]
            else
              default
            end
          else
            default
          end
        end
      end
    end
  end
end
