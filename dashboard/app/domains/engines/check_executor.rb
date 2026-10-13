# frozen_string_literal: true

module Engines
  # Handles asynchronous host and service check executions, state machine
  # transitions (SOFT vs HARD), flap detection, logging, and alert dispatches.
  class CheckExecutor
    attr_reader :config_catalog, :worker_pool, :host_states, :service_states,
                :host_histories, :service_histories, :mutex, :log_file_path

    def initialize(config_catalog:, worker_pool:, host_states:, service_states:,
                   host_histories:, service_histories:, mutex:, log_file_path:)
      @config_catalog = config_catalog
      @worker_pool = worker_pool
      @host_states = host_states
      @service_states = service_states
      @host_histories = host_histories
      @service_histories = service_histories
      @mutex = mutex
      @log_file_path = log_file_path
    end

    def update_catalog!(new_catalog)
      @config_catalog = new_catalog
    end

    def execute_event(event)
      case event.type
      when :host_check
        execute_host_check(event)
      when :service_check
        execute_service_check(event)
      end
    end

    def execute_host_check(event)
      host_name = event.target
      cmd = event.payload[:command]
      host_data = event.payload[:host_data] || {}
      max_attempts = (host_data['max_check_attempts'] || 3).to_i

      Thread.new do
        resolved_cmd = Statuses::Services::MacroResolver.resolve_command(
          cmd,
          catalog: @config_catalog,
          host: host_data
        )
        result = @worker_pool.run_job(resolved_cmd, timeout: 10.0)
        parsed = Statuses::Services::PerfdataParser.parse(result.output)

        @mutex.synchronize do
          prev = @host_states[host_name] || {}
          prev_state = prev['current_state'].to_i
          raw_exit = result.exit_code

          calculated_state = raw_exit == 0 ? 0 : 1

          # Host Reachability Evaluation (Parent Hierarchy)
          parents = host_data['parents'].to_s.split(',').map(&:strip)
          if calculated_state > 0 && parents.any?
            parent_states = parents.map { |p| @host_states.dig(p, 'current_state').to_i }
            calculated_state = 2 if parent_states.any? { |st| st > 0 } # UNREACHABLE
          end

          # SOFT vs HARD state transition
          attempts = prev['current_attempt'].to_i
          state_type = prev['state_type'].to_i

          if calculated_state == 0
            attempts = 1
            state_type = 1 # HARD OK
          else
            attempts += 1
            state_type = attempts >= max_attempts ? 1 : 0
          end

          # Flap Detection History
          @host_histories[host_name] ||= []
          @host_histories[host_name] << calculated_state
          @host_histories[host_name].shift if @host_histories[host_name].size > 21

          flap_eval = Statuses::Services::FlapDetector.evaluate(
            @host_histories[host_name],
            current_flapping: prev['is_flapping'].to_i == 1
          )

          state_name = case calculated_state
                       when 0 then 'UP'
                       when 1 then 'DOWN'
                       else 'UNREACHABLE'
                       end

          color = case calculated_state
                  when 0 then "\e[32m"
                  when 1 then "\e[31m"
                  else "\e[33m"
                  end

          type_str = state_type == 1 ? 'HARD' : 'SOFT'
          flap_str = flap_eval.flapping? ? ' \e[35m[FLAPPING]\e[0m' : ''

          puts "#{color}[HOST CHECK]\e[0m #{Time.now.strftime('%H:%M:%S')} #{host_name.ljust(14)} => #{state_name} (#{type_str} #{attempts}/#{max_attempts})#{flap_str} | #{parsed.short_output}"

          if prev_state != calculated_state || prev.empty?
            Statuses::Services::DaemonLogger.log_host_event(
              host: host_name,
              state: state_name,
              state_type: type_str,
              attempt: "#{attempts}/#{max_attempts}",
              output: parsed.short_output,
              log_path: @log_file_path
            )
          end

          if state_type == 1 && prev_state != calculated_state && calculated_state > 0
            dispatch_alert(host_name: host_name, service_desc: nil, status: state_name, output: parsed.short_output)
          elsif state_type == 1 && prev_state > 0 && calculated_state == 0
            dispatch_alert(host_name: host_name, service_desc: nil, status: 'RECOVERY', output: "Host recovered: #{parsed.short_output}")
          end

          @host_states[host_name] = {
            'host_name' => host_name,
            'current_state' => calculated_state,
            'last_state' => prev_state,
            'state_type' => state_type,
            'current_attempt' => attempts,
            'max_attempts' => max_attempts,
            'plugin_output' => parsed.short_output,
            'perf_data' => parsed.perf_data_string,
            'last_check' => Time.now.to_i,
            'execution_time' => result.execution_time,
            'is_flapping' => flap_eval.flapping? ? 1 : 0,
            'percent_state_change' => flap_eval.percent_state_change,
            'notifications_enabled' => 1
          }
        end
      end
    end

    def execute_service_check(event)
      payload = event.payload || {}
      host_name = payload[:host_name]
      svc_desc = payload[:service_description]
      cmd = payload[:command]
      svc_data = payload[:svc_data] || {}
      host_data = @config_catalog.hosts[host_name] || {}
      max_attempts = (svc_data['max_check_attempts'] || 3).to_i

      Thread.new do
        resolved_cmd = Statuses::Services::MacroResolver.resolve_command(
          cmd,
          catalog: @config_catalog,
          host: host_data,
          service: svc_data
        )
        result = @worker_pool.run_job(resolved_cmd, timeout: 10.0)
        parsed = Statuses::Services::PerfdataParser.parse(result.output)

        @mutex.synchronize do
          @service_states[host_name] ||= {}
          prev = @service_states[host_name][svc_desc] || {}
          prev_state = prev['current_state'].to_i
          new_state = result.exit_code

          attempts = prev['current_attempt'].to_i
          state_type = prev['state_type'].to_i

          if new_state == 0
            attempts = 1
            state_type = 1 # HARD OK
          else
            attempts += 1
            state_type = attempts >= max_attempts ? 1 : 0
          end

          key = "#{host_name}/#{svc_desc}"
          @service_histories[key] ||= []
          @service_histories[key] << new_state
          @service_histories[key].shift if @service_histories[key].size > 21

          flap_eval = Statuses::Services::FlapDetector.evaluate(
            @service_histories[key],
            current_flapping: prev['is_flapping'].to_i == 1
          )

          color = case new_state
                  when 0 then "\e[32m"
                  when 1 then "\e[33m"
                  when 2 then "\e[31m"
                  else "\e[35m"
                  end

          type_str = state_type == 1 ? 'HARD' : 'SOFT'
          flap_str = flap_eval.flapping? ? ' \e[35m[FLAPPING]\e[0m' : ''

          puts "#{color}[SVC CHECK]\e[0m  #{Time.now.strftime('%H:%M:%S')} #{host_name}/#{svc_desc.ljust(18)} => #{result.status_name} (#{type_str} #{attempts}/#{max_attempts})#{flap_str} | #{parsed.short_output}"

          if prev_state != new_state || prev.empty?
            Statuses::Services::DaemonLogger.log_service_event(
              host: host_name,
              service: svc_desc,
              state: result.status_name,
              state_type: type_str,
              attempt: "#{attempts}/#{max_attempts}",
              output: parsed.short_output,
              log_path: @log_file_path
            )
          end

          if state_type == 1 && prev_state != new_state && new_state > 0
            dispatch_alert(host_name: host_name, service_desc: svc_desc, status: result.status_name, output: parsed.short_output)
          elsif state_type == 1 && prev_state > 0 && new_state == 0
            dispatch_alert(host_name: host_name, service_desc: svc_desc, status: 'RECOVERY', output: "Service recovered: #{parsed.short_output}")
          end

          @service_states[host_name][svc_desc] = {
            'host_name' => host_name,
            'service_description' => svc_desc,
            'current_state' => new_state,
            'last_state' => prev_state,
            'state_type' => state_type,
            'current_attempt' => attempts,
            'max_attempts' => max_attempts,
            'plugin_output' => parsed.short_output,
            'perf_data' => parsed.perf_data_string,
            'last_check' => Time.now.to_i,
            'execution_time' => result.execution_time,
            'is_flapping' => flap_eval.flapping? ? 1 : 0,
            'percent_state_change' => flap_eval.percent_state_change,
            'notifications_enabled' => 1
          }
        end
      end
    end

    def dispatch_alert(host_name:, service_desc:, status:, output:)
      Thread.new do
        target_obj = { notifications_enabled: 1 }
        viability = Statuses::Services::NotificationViability.check(target_obj)
        if viability.viable?
          puts "🔔 [ALERT DISPATCH] #{status}: #{host_name} #{service_desc} => #{output}"
          Statuses::Services::DaemonLogger.log_notification(
            type: status,
            host: host_name,
            service: service_desc,
            contact: 'nagiosadmin',
            output: output,
            log_path: @log_file_path
          )
          Statuses::Services::NotificationService.deliver_alert(
            host_name: host_name,
            service_desc: service_desc,
            status: status,
            plugin_output: output
          )
        end
      end
    end
  end
end
