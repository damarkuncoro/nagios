# frozen_string_literal: true

module Engines
  # Mutates in-memory state and event queue based on commands received via the FIFO pipe.
  class ExternalCommandApplier
    attr_reader :config_catalog, :event_queue, :host_states, :service_states,
                :comments, :downtimes, :mutex
    attr_accessor :notifications_enabled

    def initialize(config_catalog:, event_queue:, host_states:, service_states:,
                   comments:, downtimes:, mutex:, notifications_enabled: 1)
      @config_catalog = config_catalog
      @event_queue = event_queue
      @host_states = host_states
      @service_states = service_states
      @comments = comments
      @downtimes = downtimes
      @mutex = mutex
      @notifications_enabled = notifications_enabled
    end

    def update_catalog!(new_catalog)
      @config_catalog = new_catalog
    end

    # Applies command and returns [reload_requested, state_modified]
    def apply!(result)
      cmd_name = result.command
      data = result.data || {}
      state_modified = false
      reload_requested = false

      @mutex.synchronize do
        case cmd_name
        when 'RELOAD_CONFIG'
          reload_requested = true
        when 'SCHEDULE_SVC_CHECK', 'SCHEDULE_FORCED_SVC_CHECK',
             'SCHEDULE_HOST_CHECK', 'SCHEDULE_FORCED_HOST_CHECK'
          schedule_immediate_check(cmd_name, data)
        when 'PROCESS_SERVICE_CHECK_RESULT', 'PROCESS_HOST_CHECK_RESULT'
          state_modified = apply_passive_result(cmd_name, data, result)
        when 'ACKNOWLEDGE_SVC_PROBLEM', 'REMOVE_SVC_ACKNOWLEDGEMENT',
             'ACKNOWLEDGE_HOST_PROBLEM', 'REMOVE_HOST_ACKNOWLEDGEMENT'
          state_modified = apply_acknowledgment(cmd_name, data)
        when 'SCHEDULE_SVC_DOWNTIME', 'DEL_SVC_DOWNTIME',
             'SCHEDULE_HOST_DOWNTIME', 'DEL_HOST_DOWNTIME'
          state_modified = apply_downtime(cmd_name, data)
        when 'ADD_SVC_COMMENT', 'ADD_HOST_COMMENT',
             'DEL_SVC_COMMENT', 'DEL_HOST_COMMENT'
          state_modified = apply_comment(cmd_name, data)
        when 'ENABLE_NOTIFICATIONS'
          @notifications_enabled = 1
        when 'DISABLE_NOTIFICATIONS'
          @notifications_enabled = 0
        end
      end

      [reload_requested, state_modified]
    end

    private

    def schedule_immediate_check(cmd_name, data)
      if cmd_name.include?('_SVC_')
        host_name = data[:host]
        svc_desc = data[:service]
        svc_data = @config_catalog.services.find { |s| s['host_name'] == host_name && s['service_description'] == svc_desc }
        return unless svc_data

        @event_queue.schedule(
          type: :service_check,
          run_time: Time.now.to_i,
          interval: 0,
          target: "#{host_name}/#{svc_desc}",
          payload: { host_name: host_name, service_description: svc_desc, command: svc_data['check_command'] || 'true', svc_data: svc_data }
        )
        puts "⚡ [Command Applied] Immediate check scheduled for #{host_name}/#{svc_desc}"
      else
        host_name = data[:host]
        host_data = @config_catalog.hosts[host_name]
        return unless host_data

        @event_queue.schedule(
          type: :host_check,
          run_time: Time.now.to_i,
          interval: 0,
          target: host_name,
          payload: { command: host_data['check_command'] || "ping -c 1 #{host_data['address'] || '127.0.0.1'}", host_data: host_data }
        )
        puts "⚡ [Command Applied] Immediate check scheduled for host #{host_name}"
      end
    end

    def apply_passive_result(cmd_name, data, result)
      perfdata = data[:perfdata]
      ret_code = data[:return_code].to_i

      if cmd_name == 'PROCESS_SERVICE_CHECK_RESULT'
        host_name, svc_desc = data[:host], data[:service]
        @service_states[host_name] ||= {}
        prev = @service_states[host_name][svc_desc] || {}
        @service_states[host_name][svc_desc] = {
          'host_name' => host_name,
          'service_description' => svc_desc,
          'current_state' => ret_code,
          'last_state' => prev['current_state'].to_i,
          'state_type' => 1,
          'current_attempt' => 1,
          'max_attempts' => (prev['max_attempts'] || 3).to_i,
          'plugin_output' => perfdata.respond_to?(:short_output) ? perfdata.short_output : result.args[3].to_s,
          'perf_data' => perfdata.respond_to?(:perf_data_string) ? perfdata.perf_data_string : '',
          'last_check' => Time.now.to_i,
          'execution_time' => 0.001,
          'is_flapping' => 0,
          'percent_state_change' => 0.0,
          'notifications_enabled' => prev['notifications_enabled'] || 1
        }
        puts "⚡ [Command Applied] Passive service result stored for #{host_name}/#{svc_desc} (State: #{ret_code})"
      else
        host_name = data[:host]
        prev = @host_states[host_name] || {}
        @host_states[host_name] = {
          'host_name' => host_name,
          'current_state' => ret_code == 0 ? 0 : 1,
          'last_state' => prev['current_state'].to_i,
          'state_type' => 1,
          'current_attempt' => 1,
          'max_attempts' => (prev['max_attempts'] || 3).to_i,
          'plugin_output' => perfdata.respond_to?(:short_output) ? perfdata.short_output : result.args[2].to_s,
          'perf_data' => perfdata.respond_to?(:perf_data_string) ? perfdata.perf_data_string : '',
          'last_check' => Time.now.to_i,
          'execution_time' => 0.001,
          'is_flapping' => 0,
          'percent_state_change' => 0.0,
          'notifications_enabled' => prev['notifications_enabled'] || 1
        }
        puts "⚡ [Command Applied] Passive host result stored for #{host_name} (State: #{ret_code})"
      end
      true
    end

    def apply_acknowledgment(cmd_name, data)
      host_name = data[:host]
      case cmd_name
      when 'ACKNOWLEDGE_SVC_PROBLEM'
        svc = @service_states.dig(host_name, data[:service])
        return false unless svc

        svc['problem_has_been_acknowledged'] = 1
        svc['acknowledgement_type'] = 1
        @comments << build_comment(host_name, data[:service], data[:author], data[:comment], 4)
      when 'REMOVE_SVC_ACKNOWLEDGEMENT'
        svc = @service_states.dig(host_name, data[:service])
        return false unless svc

        svc['problem_has_been_acknowledged'] = 0
        svc['acknowledgement_type'] = 0
      when 'ACKNOWLEDGE_HOST_PROBLEM'
        host = @host_states[host_name]
        return false unless host

        host['problem_has_been_acknowledged'] = 1
        host['acknowledgement_type'] = 1
        @comments << build_comment(host_name, nil, data[:author], data[:comment], 4)
      when 'REMOVE_HOST_ACKNOWLEDGEMENT'
        host = @host_states[host_name]
        return false unless host

        host['problem_has_been_acknowledged'] = 0
        host['acknowledgement_type'] = 0
      end
      true
    end

    def apply_downtime(cmd_name, data)
      if cmd_name == 'DEL_SVC_DOWNTIME' || cmd_name == 'DEL_HOST_DOWNTIME'
        @downtimes.reject! { |d| d['downtime_id'] == data[:downtime_id] }
      else
        entry = {
          'downtime_id' => data[:downtime_id],
          'host_name' => data[:host],
          'start_time' => data[:start_time],
          'end_time' => data[:end_time],
          'fixed' => data[:fixed] ? 1 : 0,
          'duration' => data[:duration],
          'author' => data[:author],
          'comment' => data[:comment],
          'entry_time' => Time.now.to_i
        }
        entry['service_description'] = data[:service] if data[:service]
        @downtimes << entry
      end
      true
    end

    def apply_comment(cmd_name, data)
      if cmd_name.start_with?('DEL_')
        @comments.reject! { |c| c['comment_id'] == data[:comment_id] }
      else
        @comments << build_comment(data[:host], data[:service], data[:author], data[:comment_data] || data[:comment], 1, data[:comment_id])
      end
      true
    end

    def build_comment(host, svc, author, text, entry_type, cid = nil)
      item = {
        'comment_id' => cid || rand(1000..99_999),
        'host_name' => host,
        'author' => author,
        'comment_data' => text || 'Comment',
        'entry_time' => Time.now.to_i,
        'entry_type' => entry_type
      }
      item['service_description'] = svc if svc
      item['persistent'] = 1 if entry_type == 4
      item
    end
  end
end
