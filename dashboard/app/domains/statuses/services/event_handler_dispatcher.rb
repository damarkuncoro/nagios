# frozen_string_literal: true

module Statuses
  module Services
    # Adopts host and service state change event handlers from base/sehandlers.c
    # Implements handle_service_event and handle_host_event with macro expansion and broker events.
    class EventHandlerDispatcher
      DispatchResult = Struct.new(
        :dispatched,
        :command_line,
        :reason,
        :target_name,
        keyword_init: true
      ) do
        def dispatched?
          dispatched == true
        end
      end

      class << self
        # Dispatches service event handler on state transition (base/sehandlers.c: handle_service_event)
        def handle_service_event(service:,
                                 host:,
                                 old_state:,
                                 new_state:,
                                 state_type: 'HARD',
                                 attempt: 1,
                                 max_attempts: 3,
                                 global_handlers_enabled: true,
                                 global_handler_cmd: nil,
                                 runner: nil,
                                 event_broker: Events::Broker)
          h_name = host.is_a?(Hash) ? host['name'] : (host.respond_to?(:name) ? host.name : host.to_s)
          s_desc = service.is_a?(Hash) ? service['description'] : (service.respond_to?(:description) ? service.description : service.to_s)
          target_identifier = "#{h_name}/#{s_desc}"

          # 1. Check global setting
          unless global_handlers_enabled
            return DispatchResult.new(
              dispatched: false,
              command_line: nil,
              reason: 'Global event handlers are disabled',
              target_name: target_identifier
            )
          end

          # 2. Check service-level event handler setting
          s_enabled = service.is_a?(Hash) ? service['event_handler_enabled'] : (service.respond_to?(:event_handler_enabled) ? service.event_handler_enabled : true)
          if s_enabled == false
            return DispatchResult.new(
              dispatched: false,
              command_line: nil,
              reason: 'Event handler is disabled for this service',
              target_name: target_identifier
            )
          end

          # 3. Determine command template (service-specific or global fallback)
          cmd_template = (service.is_a?(Hash) ? service['event_handler'] : service.try(:event_handler)).presence || global_handler_cmd
          if cmd_template.blank?
            return DispatchResult.new(
              dispatched: false,
              command_line: nil,
              reason: 'No event handler command configured',
              target_name: target_identifier
            )
          end

          # 4. Resolve macros (base/sehandlers.c line 187, 247)
          command_line = MacroResolver.resolve(
            cmd_template,
            host: host,
            service: service,
            bang_args: [new_state.to_s, state_type.to_s, attempt.to_s]
          )

          # Expand specific state handler macros
          command_line.gsub!('$SERVICESTATE$', new_state.to_s.upcase)
          command_line.gsub!('$SERVICESTATETYPE$', state_type.to_s.upcase)
          command_line.gsub!('$SERVICEATTEMPT$', "#{attempt}/#{max_attempts}")
          command_line.gsub!('$LASTSERVICESTATE$', old_state.to_s.upcase)

          # 5. Notify Event Broker (NEB statechange data broker_statechange_data line 181)
          event_broker.publish(
            Events::Broker::STATE_CHANGE,
            {
              type: 'service',
              host: h_name,
              service: s_desc,
              old_state: old_state,
              new_state: new_state,
              state_type: state_type,
              attempt: "#{attempt}/#{max_attempts}",
              command: command_line
            },
            source: 'EventHandlerDispatcher'
          )

          # 6. Execute runner if provided
          runner&.call(command_line)

          DispatchResult.new(
            dispatched: true,
            command_line: command_line,
            reason: 'Service event handler dispatched successfully',
            target_name: target_identifier
          )
        end

        # Dispatches host event handler on state transition (base/sehandlers.c: handle_host_event)
        def handle_host_event(host:,
                              old_state:,
                              new_state:,
                              state_type: 'HARD',
                              attempt: 1,
                              max_attempts: 3,
                              global_handlers_enabled: true,
                              global_handler_cmd: nil,
                              runner: nil,
                              event_broker: Events::Broker)
          h_name = host.is_a?(Hash) ? host['name'] : (host.respond_to?(:name) ? host.name : host.to_s)

          # 1. Check global setting
          unless global_handlers_enabled
            return DispatchResult.new(
              dispatched: false,
              command_line: nil,
              reason: 'Global event handlers are disabled',
              target_name: h_name
            )
          end

          # 2. Check host-level event handler setting
          h_enabled = host.is_a?(Hash) ? host['event_handler_enabled'] : (host.respond_to?(:event_handler_enabled) ? host.event_handler_enabled : true)
          if h_enabled == false
            return DispatchResult.new(
              dispatched: false,
              command_line: nil,
              reason: 'Event handler is disabled for this host',
              target_name: h_name
            )
          end

          # 3. Determine command template
          cmd_template = (host.is_a?(Hash) ? host['event_handler'] : host.try(:event_handler)).presence || global_handler_cmd
          if cmd_template.blank?
            return DispatchResult.new(
              dispatched: false,
              command_line: nil,
              reason: 'No event handler command configured',
              target_name: h_name
            )
          end

          # 4. Resolve macros
          command_line = MacroResolver.resolve(
            cmd_template,
            host: host,
            bang_args: [new_state.to_s, state_type.to_s, attempt.to_s]
          )

          command_line.gsub!('$HOSTSTATE$', new_state.to_s.upcase)
          command_line.gsub!('$HOSTSTATETYPE$', state_type.to_s.upcase)
          command_line.gsub!('$HOSTATTEMPT$', "#{attempt}/#{max_attempts}")
          command_line.gsub!('$LASTHOSTSTATE$', old_state.to_s.upcase)

          # 5. Notify Event Broker
          event_broker.publish(
            Events::Broker::STATE_CHANGE,
            {
              type: 'host',
              host: h_name,
              old_state: old_state,
              new_state: new_state,
              state_type: state_type,
              attempt: "#{attempt}/#{max_attempts}",
              command: command_line
            },
            source: 'EventHandlerDispatcher'
          )

          # 6. Execute runner if provided
          runner&.call(command_line)

          DispatchResult.new(
            dispatched: true,
            command_line: command_line,
            reason: 'Host event handler dispatched successfully',
            target_name: h_name
          )
        end
      end
    end
  end
end
