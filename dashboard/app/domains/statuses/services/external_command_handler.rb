# frozen_string_literal: true

module Statuses
  module Services
    # Adopts external command processing from base/commands.c
    # Parses FIFO/file-based Nagios external commands (`[timestamp] COMMAND_NAME;arg1;arg2;...`),
    # validates arguments, dispatches state updates, logs actions, and notifies broker/radio channels.
    class ExternalCommandHandler
      CommandResult = Struct.new(
        :success,
        :command,
        :entry_time,
        :args,
        :message,
        :data,
        keyword_init: true
      ) do
        def success?
          success == true
        end
      end

      COMMAND_HANDLERS = {
        'PROCESS_SERVICE_CHECK_RESULT' => :process_service_check_result,
        'PROCESS_HOST_CHECK_RESULT' => :process_host_check_result,
        'SCHEDULE_SVC_CHECK' => :schedule_svc_check,
        'SCHEDULE_FORCED_SVC_CHECK' => :schedule_svc_check,
        'SCHEDULE_HOST_CHECK' => :schedule_host_check,
        'SCHEDULE_FORCED_HOST_CHECK' => :schedule_host_check,
        'SCHEDULE_HOST_SVC_CHECKS' => :schedule_host_svc_checks,
        'SCHEDULE_FORCED_HOST_SVC_CHECKS' => :schedule_host_svc_checks,
        'ACKNOWLEDGE_SVC_PROBLEM' => :acknowledge_svc_problem,
        'REMOVE_SVC_ACKNOWLEDGEMENT' => :remove_svc_acknowledgement,
        'ACKNOWLEDGE_HOST_PROBLEM' => :acknowledge_host_problem,
        'REMOVE_HOST_ACKNOWLEDGEMENT' => :remove_host_acknowledgement,
        'SCHEDULE_SVC_DOWNTIME' => :schedule_svc_downtime,
        'DEL_SVC_DOWNTIME' => :del_svc_downtime,
        'SCHEDULE_HOST_DOWNTIME' => :schedule_host_downtime,
        'DEL_HOST_DOWNTIME' => :del_host_downtime,
        'ENABLE_NOTIFICATIONS' => :enable_notifications,
        'DISABLE_NOTIFICATIONS' => :disable_notifications,
        'ENABLE_SVC_NOTIFICATIONS' => :enable_svc_notifications,
        'DISABLE_SVC_NOTIFICATIONS' => :disable_svc_notifications,
        'ENABLE_HOST_NOTIFICATIONS' => :enable_host_notifications,
        'DISABLE_HOST_NOTIFICATIONS' => :disable_host_notifications,
        'ENABLE_SVC_CHECK' => :enable_svc_check,
        'DISABLE_SVC_CHECK' => :disable_svc_check,
        'ENABLE_HOST_CHECK' => :enable_host_check,
        'DISABLE_HOST_CHECK' => :disable_host_check,
        'ENABLE_FLAP_DETECTION' => :enable_flap_detection,
        'DISABLE_FLAP_DETECTION' => :disable_flap_detection,
        'ENABLE_SVC_FLAP_DETECTION' => :enable_svc_flap_detection,
        'DISABLE_SVC_FLAP_DETECTION' => :disable_svc_flap_detection,
        'ENABLE_HOST_FLAP_DETECTION' => :enable_host_flap_detection,
        'DISABLE_HOST_FLAP_DETECTION' => :disable_host_flap_detection,
        'ADD_SVC_COMMENT' => :add_svc_comment,
        'DEL_SVC_COMMENT' => :del_svc_comment,
        'ADD_HOST_COMMENT' => :add_host_comment,
        'DEL_HOST_COMMENT' => :del_host_comment,
        'SAVE_STATE_INFORMATION' => :save_state_information,
        'READ_STATE_INFORMATION' => :read_state_information,
        'RELOAD_CONFIG' => :reload_config
      }.freeze

      class << self
        def process(raw_command_line, engine: nil)
          new(engine: engine).process(raw_command_line)
        end

        def process_batch(command_lines, engine: nil)
          handler = new(engine: engine)
          Array(command_lines).map { |line| handler.process(line) }
        end
      end

      def initialize(
        engine: nil,
        broker: Statuses::Events::Broker,
        radio: EventRadioDispatcher.instance,
        logger: DaemonLogger
      )
        @engine = engine || (defined?(Engines::NagiosEngine) ? Engines::NagiosEngine : nil)
        @broker = broker
        @radio = radio
        @logger = logger
      end

      # Parses and executes external command line (base/commands.c: process_external_command1 & 2)
      def process(raw_line)
        return error_result('EMPTY', 0, [], 'Command line cannot be empty') if raw_line.to_s.strip.empty?

        entry_time, command_name, args = parse_command_line(raw_line.to_s.strip)

        handler_method = COMMAND_HANDLERS[command_name]
        unless handler_method
          return error_result(
            command_name,
            entry_time,
            args,
            "Unknown or unsupported external command: '#{command_name}'"
          )
        end

        result = send(handler_method, entry_time, args)

        # Notify broker, radio channel, and daemon logger
        log_command(command_name, entry_time, args, result)
        dispatch_notifications(command_name, entry_time, args, result)

        result
      rescue StandardError => e
        error_result(command_name || 'UNKNOWN', entry_time || 0, args || [], "Execution error: #{e.message}")
      end

      private

      # Parses format: "[timestamp] COMMAND_NAME;arg1;arg2;..." or "COMMAND_NAME;arg1;..."
      def parse_command_line(line)
        now_ts = (Time.respond_to?(:current) ? Time.current : Time.now).to_i
        entry_time = now_ts
        cmd_part = line

        if line =~ /\A\[(\d+)\]\s*(.*)\z/
          entry_time = Regexp.last_match(1).to_i
          cmd_part = Regexp.last_match(2).strip
        end

        tokens = cmd_part.split(';', 2)
        command_name = tokens.first.to_s.strip.upcase
        raw_args = tokens[1].to_s

        args =
          case command_name
          when 'PROCESS_SERVICE_CHECK_RESULT'
            raw_args.split(';', 4)
          when 'PROCESS_HOST_CHECK_RESULT'
            raw_args.split(';', 3)
          else
            raw_args.split(';')
          end

        [entry_time, command_name, args]
      end

      # PROCESS_SERVICE_CHECK_RESULT;host;service;return_code;plugin_output
      def process_service_check_result(entry_time, args)
        host, service, code_str, output = args
        return missing_args_result('PROCESS_SERVICE_CHECK_RESULT', entry_time, args, 4) if [host, service, code_str].any?(&:nil?)

        code = code_str.to_i
        perfdata = PerfdataParser.parse(output.to_s)

        success_result(
          'PROCESS_SERVICE_CHECK_RESULT',
          entry_time,
          args,
          "Passive check result accepted for #{host}/#{service} (Status: #{code})",
          host: host,
          service: service,
          return_code: code,
          perfdata: perfdata
        )
      end

      # PROCESS_HOST_CHECK_RESULT;host;return_code;plugin_output
      def process_host_check_result(entry_time, args)
        host, code_str, output = args
        return missing_args_result('PROCESS_HOST_CHECK_RESULT', entry_time, args, 3) if [host, code_str].any?(&:nil?)

        code = code_str.to_i
        perfdata = PerfdataParser.parse(output.to_s)

        success_result(
          'PROCESS_HOST_CHECK_RESULT',
          entry_time,
          args,
          "Passive host check result accepted for #{host} (Status: #{code})",
          host: host,
          return_code: code,
          perfdata: perfdata
        )
      end

      # SCHEDULE_SVC_CHECK / SCHEDULE_FORCED_SVC_CHECK;host;service;check_time
      def schedule_svc_check(entry_time, args)
        host, service, check_time = args
        return missing_args_result('SCHEDULE_SVC_CHECK', entry_time, args, 3) if [host, service].any?(&:nil?)

        target_time = (check_time && !check_time.to_s.strip.empty?) ? check_time.to_i : entry_time
        success_result(
          'SCHEDULE_SVC_CHECK',
          entry_time,
          args,
          "Service check scheduled for #{host}/#{service} at #{Time.at(target_time)}",
          host: host,
          service: service,
          check_time: target_time
        )
      end

      # SCHEDULE_HOST_CHECK / SCHEDULE_FORCED_HOST_CHECK;host;check_time
      def schedule_host_check(entry_time, args)
        host, check_time = args
        return missing_args_result('SCHEDULE_HOST_CHECK', entry_time, args, 2) if host.nil?

        target_time = (check_time && !check_time.to_s.strip.empty?) ? check_time.to_i : entry_time
        success_result(
          'SCHEDULE_HOST_CHECK',
          entry_time,
          args,
          "Host check scheduled for #{host} at #{Time.at(target_time)}",
          host: host,
          check_time: target_time
        )
      end

      # SCHEDULE_HOST_SVC_CHECKS / SCHEDULE_FORCED_HOST_SVC_CHECKS;host;check_time
      def schedule_host_svc_checks(entry_time, args)
        host, check_time = args
        return missing_args_result('SCHEDULE_HOST_SVC_CHECKS', entry_time, args, 2) if host.nil?

        target_time = (check_time && !check_time.to_s.strip.empty?) ? check_time.to_i : entry_time
        success_result(
          'SCHEDULE_HOST_SVC_CHECKS',
          entry_time,
          args,
          "Host & all service checks scheduled for #{host} at #{Time.at(target_time)}",
          host: host,
          check_time: target_time
        )
      end

      # ACKNOWLEDGE_SVC_PROBLEM;host;service;sticky;notify;persistent;author;comment
      def acknowledge_svc_problem(entry_time, args)
        host, service, _sticky, _notify, _persistent, author, comment = args
        return missing_args_result('ACKNOWLEDGE_SVC_PROBLEM', entry_time, args, 7) if [host, service, author].any?(&:nil?)

        success_result(
          'ACKNOWLEDGE_SVC_PROBLEM',
          entry_time,
          args,
          "Problem acknowledged for service #{host}/#{service} by #{author}",
          host: host,
          service: service,
          author: author,
          comment: comment
        )
      end

      # REMOVE_SVC_ACKNOWLEDGEMENT;host;service
      def remove_svc_acknowledgement(entry_time, args)
        host, service = args
        return missing_args_result('REMOVE_SVC_ACKNOWLEDGEMENT', entry_time, args, 2) if [host, service].any?(&:nil?)

        success_result(
          'REMOVE_SVC_ACKNOWLEDGEMENT',
          entry_time,
          args,
          "Acknowledgement removed for service #{host}/#{service}",
          host: host,
          service: service
        )
      end

      # ACKNOWLEDGE_HOST_PROBLEM;host;sticky;notify;persistent;author;comment
      def acknowledge_host_problem(entry_time, args)
        host, _sticky, _notify, _persistent, author, comment = args
        return missing_args_result('ACKNOWLEDGE_HOST_PROBLEM', entry_time, args, 6) if [host, author].any?(&:nil?)

        success_result(
          'ACKNOWLEDGE_HOST_PROBLEM',
          entry_time,
          args,
          "Problem acknowledged for host #{host} by #{author}",
          host: host,
          author: author,
          comment: comment
        )
      end

      # REMOVE_HOST_ACKNOWLEDGEMENT;host
      def remove_host_acknowledgement(entry_time, args)
        host = args.first
        return missing_args_result('REMOVE_HOST_ACKNOWLEDGEMENT', entry_time, args, 1) if host.nil?

        success_result(
          'REMOVE_HOST_ACKNOWLEDGEMENT',
          entry_time,
          args,
          "Acknowledgement removed for host #{host}",
          host: host
        )
      end

      # SCHEDULE_SVC_DOWNTIME;host;service;start;end;fixed;trigger_id;duration;author;comment
      def schedule_svc_downtime(entry_time, args)
        host, service, start_t, end_t, fixed, trigger_id, duration, author, comment = args
        return missing_args_result('SCHEDULE_SVC_DOWNTIME', entry_time, args, 9) if [host, service, start_t, end_t].any?(&:nil?)

        downtime_id = rand(1000..99_999)
        success_result(
          'SCHEDULE_SVC_DOWNTIME',
          entry_time,
          args,
          "Downtime ID ##{downtime_id} scheduled for service #{host}/#{service}",
          downtime_id: downtime_id,
          host: host,
          service: service,
          start_time: start_t.to_i,
          end_time: end_t.to_i,
          fixed: fixed.to_i == 1,
          duration: duration.to_i,
          author: author,
          comment: comment
        )
      end

      # DEL_SVC_DOWNTIME;downtime_id
      def del_svc_downtime(entry_time, args)
        id = args.first
        return missing_args_result('DEL_SVC_DOWNTIME', entry_time, args, 1) if id.nil?

        success_result(
          'DEL_SVC_DOWNTIME',
          entry_time,
          args,
          "Cancelled service downtime ID ##{id}",
          downtime_id: id.to_i
        )
      end

      # SCHEDULE_HOST_DOWNTIME;host;start;end;fixed;trigger_id;duration;author;comment
      def schedule_host_downtime(entry_time, args)
        host, start_t, end_t, fixed, _trigger_id, duration, author, comment = args
        return missing_args_result('SCHEDULE_HOST_DOWNTIME', entry_time, args, 8) if [host, start_t, end_t].any?(&:nil?)

        downtime_id = rand(1000..99_999)
        success_result(
          'SCHEDULE_HOST_DOWNTIME',
          entry_time,
          args,
          "Downtime ID ##{downtime_id} scheduled for host #{host}",
          downtime_id: downtime_id,
          host: host,
          start_time: start_t.to_i,
          end_time: end_t.to_i,
          fixed: fixed.to_i == 1,
          duration: duration.to_i,
          author: author,
          comment: comment
        )
      end

      # DEL_HOST_DOWNTIME;downtime_id
      def del_host_downtime(entry_time, args)
        id = args.first
        return missing_args_result('DEL_HOST_DOWNTIME', entry_time, args, 1) if id.nil?

        success_result(
          'DEL_HOST_DOWNTIME',
          entry_time,
          args,
          "Cancelled host downtime ID ##{id}",
          downtime_id: id.to_i
        )
      end

      # ENABLE_NOTIFICATIONS / DISABLE_NOTIFICATIONS
      def enable_notifications(entry_time, args)
        success_result('ENABLE_NOTIFICATIONS', entry_time, args, 'Global notifications enabled')
      end

      def disable_notifications(entry_time, args)
        success_result('DISABLE_NOTIFICATIONS', entry_time, args, 'Global notifications disabled')
      end

      def enable_svc_notifications(entry_time, args)
        host, service = args
        success_result('ENABLE_SVC_NOTIFICATIONS', entry_time, args, "Notifications enabled for #{host}/#{service}", host: host, service: service)
      end

      def disable_svc_notifications(entry_time, args)
        host, service = args
        success_result('DISABLE_SVC_NOTIFICATIONS', entry_time, args, "Notifications disabled for #{host}/#{service}", host: host, service: service)
      end

      def enable_host_notifications(entry_time, args)
        host = args.first
        success_result('ENABLE_HOST_NOTIFICATIONS', entry_time, args, "Notifications enabled for #{host}", host: host)
      end

      def disable_host_notifications(entry_time, args)
        host = args.first
        success_result('DISABLE_HOST_NOTIFICATIONS', entry_time, args, "Notifications disabled for #{host}", host: host)
      end

      def enable_svc_check(entry_time, args)
        host, service = args
        success_result('ENABLE_SVC_CHECK', entry_time, args, "Active checks enabled for #{host}/#{service}", host: host, service: service)
      end

      def disable_svc_check(entry_time, args)
        host, service = args
        success_result('DISABLE_SVC_CHECK', entry_time, args, "Active checks disabled for #{host}/#{service}", host: host, service: service)
      end

      def enable_host_check(entry_time, args)
        host = args.first
        success_result('ENABLE_HOST_CHECK', entry_time, args, "Active checks enabled for #{host}", host: host)
      end

      def disable_host_check(entry_time, args)
        host = args.first
        success_result('DISABLE_HOST_CHECK', entry_time, args, "Active checks disabled for #{host}", host: host)
      end

      def enable_flap_detection(entry_time, args)
        success_result('ENABLE_FLAP_DETECTION', entry_time, args, 'Global flap detection enabled')
      end

      def disable_flap_detection(entry_time, args)
        success_result('DISABLE_FLAP_DETECTION', entry_time, args, 'Global flap detection disabled')
      end

      def enable_svc_flap_detection(entry_time, args)
        host, service = args
        success_result('ENABLE_SVC_FLAP_DETECTION', entry_time, args, "Flap detection enabled for #{host}/#{service}", host: host, service: service)
      end

      def disable_svc_flap_detection(entry_time, args)
        host, service = args
        success_result('DISABLE_SVC_FLAP_DETECTION', entry_time, args, "Flap detection disabled for #{host}/#{service}", host: host, service: service)
      end

      def enable_host_flap_detection(entry_time, args)
        host = args.first
        success_result('ENABLE_HOST_FLAP_DETECTION', entry_time, args, "Flap detection enabled for #{host}", host: host)
      end

      def disable_host_flap_detection(entry_time, args)
        host = args.first
        success_result('DISABLE_HOST_FLAP_DETECTION', entry_time, args, "Flap detection disabled for #{host}", host: host)
      end

      def add_svc_comment(entry_time, args)
        host, service, _persistent, author, comment = args
        comment_id = rand(1000..99_999)
        success_result(
          'ADD_SVC_COMMENT',
          entry_time,
          args,
          "Comment ##{comment_id} added to service #{host}/#{service} by #{author}",
          comment_id: comment_id,
          host: host,
          service: service,
          author: author,
          comment: comment
        )
      end

      def del_svc_comment(entry_time, args)
        id = args.first
        success_result('DEL_SVC_COMMENT', entry_time, args, "Deleted service comment ##{id}", comment_id: id.to_i)
      end

      def add_host_comment(entry_time, args)
        host, _persistent, author, comment = args
        comment_id = rand(1000..99_999)
        success_result(
          'ADD_HOST_COMMENT',
          entry_time,
          args,
          "Comment ##{comment_id} added to host #{host} by #{author}",
          comment_id: comment_id,
          host: host,
          author: author,
          comment: comment
        )
      end

      def del_host_comment(entry_time, args)
        id = args.first
        success_result('DEL_HOST_COMMENT', entry_time, args, "Deleted host comment ##{id}", comment_id: id.to_i)
      end

      def save_state_information(entry_time, args)
        success_result('SAVE_STATE_INFORMATION', entry_time, args, 'Saved runtime retention state')
      end

      def read_state_information(entry_time, args)
        success_result('READ_STATE_INFORMATION', entry_time, args, 'Loaded runtime retention state')
      end

      def reload_config(entry_time, args)
        success_result('RELOAD_CONFIG', entry_time, args, 'Object configuration reload requested')
      end

      # Helpers
      def success_result(command, entry_time, args, message, **data)
        CommandResult.new(
          success: true,
          command: command,
          entry_time: entry_time,
          args: args,
          message: message,
          data: data
        )
      end

      def error_result(command, entry_time, args, message)
        CommandResult.new(
          success: false,
          command: command,
          entry_time: entry_time,
          args: args,
          message: message,
          data: {}
        )
      end

      def missing_args_result(command, entry_time, args, expected)
        error_result(
          command,
          entry_time,
          args,
          "Invalid parameter count for #{command} (Expected >= #{expected}, got #{args.size})"
        )
      end

      def log_command(command, entry_time, args, result)
        status_txt = result.success? ? 'SUCCESS' : 'FAILED'
        @logger.format_entry("EXTERNAL COMMAND: [#{entry_time}] #{command};#{args.join(';')} [#{status_txt}]")
      rescue StandardError
        # Non-fatal logging
      end

      def dispatch_notifications(command, entry_time, args, result)
        @broker.publish(:command_executed, command: command, entry_time: entry_time, args: args, result: result) if @broker.respond_to?(:publish)
        @radio.broadcast(:commands, { command: command, success: result.success?, time: entry_time, message: result.message }) if @radio.respond_to?(:broadcast)
      rescue StandardError
        # Non-fatal dispatching
      end
    end
  end
end
