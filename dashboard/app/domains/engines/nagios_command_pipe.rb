module Engines
  module NagiosCommandPipe
    def write_cmd(command)
      pipe_path = self.class::NAGIOS_CMD_PIPE
      if File.exist?(pipe_path)
        File.open(pipe_path, 'a') { |f| f.write(command) }
        true
      else
        Rails.logger.error("Nagios FIFO pipe tidak ditemukan di #{pipe_path}")
        false
      end
    end

    def delete_comment(comment_id)
      timestamp = Time.now.to_i
      write_cmd("[#{timestamp}] DEL_SVC_COMMENT;#{comment_id}\n")
      write_cmd("[#{timestamp}] DEL_HOST_COMMENT;#{comment_id}\n")
    end

    def add_service_comment(host_name, service_desc, author, comment)
      timestamp = Time.now.to_i
      command = "[#{timestamp}] ADD_SVC_COMMENT;#{host_name};#{service_desc};1;#{author};#{comment}\n"
      write_cmd(command)
    end

    def add_host_comment(host_name, author, comment)
      timestamp = Time.now.to_i
      command = "[#{timestamp}] ADD_HOST_COMMENT;#{host_name};1;#{author};#{comment}\n"
      write_cmd(command)
    end

    def schedule_forced_host_svc_checks(host_name)
      timestamp = Time.now.to_i
      command = "[#{timestamp}] SCHEDULE_FORCED_HOST_SVC_CHECKS;#{host_name};#{timestamp}\n"
      write_cmd(command)
    end

    def schedule_host_recheck(host_name)
      timestamp = Time.now.to_i
      command = "[#{timestamp}] SCHEDULE_FORCED_HOST_CHECK;#{host_name};#{timestamp}\n"
      write_cmd(command)
    end

    def schedule_service_recheck(host_name, service_desc)
      timestamp = Time.now.to_i
      command = "[#{timestamp}] SCHEDULE_FORCED_SVC_CHECK;#{host_name};#{service_desc};#{timestamp}\n"
      write_cmd(command)
    end

    def acknowledge_service_problem(host_name, service_desc, author, comment)
      timestamp = Time.now.to_i
      command = "[#{timestamp}] ACKNOWLEDGE_SVC_PROBLEM;#{host_name};#{service_desc};2;1;1;#{author};#{comment}\n"
      write_cmd(command)
    end

    def acknowledge_host_problem(host_name, author, comment)
      timestamp = Time.now.to_i
      command = "[#{timestamp}] ACKNOWLEDGE_HOST_PROBLEM;#{host_name};2;1;1;#{author};#{comment}\n"
      write_cmd(command)
    end

    def remove_host_acknowledgement(host_name)
      timestamp = Time.now.to_i
      command = "[#{timestamp}] REMOVE_HOST_ACKNOWLEDGEMENT;#{host_name}\n"
      write_cmd(command)
    end

    def remove_service_acknowledgement(host_name, service_desc)
      timestamp = Time.now.to_i
      command = "[#{timestamp}] REMOVE_SVC_ACKNOWLEDGEMENT;#{host_name};#{service_desc}\n"
      write_cmd(command)
    end

    def schedule_service_downtime(host_name, service_desc, duration_hours: 1, author: 'nagiosadmin', comment: 'Scheduled Maintenance')
      start_time = Time.now.to_i
      end_time = start_time + (duration_hours.to_i * 3600)
      duration = duration_hours.to_i * 3600
      command = "[#{start_time}] SCHEDULE_SVC_DOWNTIME;#{host_name};#{service_desc};#{start_time};#{end_time};1;0;#{duration};#{author};#{comment}\n"
      write_cmd(command)
    end

    def schedule_host_downtime(host_name, duration_hours: 1, author: 'nagiosadmin', comment: 'Scheduled Maintenance')
      start_time = Time.now.to_i
      end_time = start_time + (duration_hours.to_i * 3600)
      duration = duration_hours.to_i * 3600
      command = "[#{start_time}] SCHEDULE_HOST_DOWNTIME;#{host_name};#{start_time};#{end_time};1;0;#{duration};#{author};#{comment}\n"
      write_cmd(command)
    end

    def schedule_host_and_services_downtime(host_name, duration_hours: 2, author: 'nagiosadmin', comment: 'Scheduled Maintenance')
      start_time = Time.now.to_i
      end_time = start_time + (duration_hours.to_i * 3600)
      duration = duration_hours.to_i * 3600
      command = "[#{start_time}] SCHEDULE_HOST_SVC_DOWNTIME;#{host_name};#{start_time};#{end_time};1;0;#{duration};#{author};#{comment}\n"
      write_cmd(command)
    end

    def cancel_downtime(downtime_id)
      timestamp = Time.now.to_i
      write_cmd("[#{timestamp}] DEL_SVC_DOWNTIME;#{downtime_id}\n")
      write_cmd("[#{timestamp}] DEL_HOST_DOWNTIME;#{downtime_id}\n")
    end

    def toggle_feature(feature_name, enable_flag)
      timestamp = Time.now.to_i
      cmd_name = case feature_name.to_s
                 when 'notifications'
                   enable_flag ? 'ENABLE_NOTIFICATIONS' : 'DISABLE_NOTIFICATIONS'
                 when 'service_checks'
                   enable_flag ? 'START_EXECUTING_SVC_CHECKS' : 'STOP_EXECUTING_SVC_CHECKS'
                 when 'flap_detection'
                   enable_flag ? 'ENABLE_FLAP_DETECTION' : 'DISABLE_FLAP_DETECTION'
                 when 'event_handlers'
                   enable_flag ? 'ENABLE_EVENT_HANDLERS' : 'DISABLE_EVENT_HANDLERS'
                 end

      return false unless cmd_name
      write_cmd("[#{timestamp}] #{cmd_name}\n")
    end

    def toggle_service_notifications(host_name, service_desc, enable_flag)
      timestamp = Time.now.to_i
      cmd_name = enable_flag ? 'ENABLE_SVC_NOTIFICATIONS' : 'DISABLE_SVC_NOTIFICATIONS'
      write_cmd("[#{timestamp}] #{cmd_name};#{host_name};#{service_desc}\n")
    end

    def toggle_service_checks(host_name, service_desc, enable_flag)
      timestamp = Time.now.to_i
      cmd_name = enable_flag ? 'ENABLE_SVC_CHECK' : 'DISABLE_SVC_CHECK'
      write_cmd("[#{timestamp}] #{cmd_name};#{host_name};#{service_desc}\n")
    end

    def toggle_host_notifications(host_name, enable_flag)
      timestamp = Time.now.to_i
      cmd_name = enable_flag ? 'ENABLE_HOST_NOTIFICATIONS' : 'DISABLE_HOST_NOTIFICATIONS'
      write_cmd("[#{timestamp}] #{cmd_name};#{host_name}\n")
    end

    def toggle_host_checks(host_name, enable_flag)
      timestamp = Time.now.to_i
      cmd_name = enable_flag ? 'ENABLE_HOST_CHECK' : 'DISABLE_HOST_CHECK'
      write_cmd("[#{timestamp}] #{cmd_name};#{host_name}\n")
    end

    def submit_passive_check(host_name, service_desc, status_code, output)
      timestamp = Time.now.to_i
      if service_desc.present?
        write_cmd("[#{timestamp}] PROCESS_SERVICE_CHECK_RESULT;#{host_name};#{service_desc};#{status_code};#{output}\n")
      else
        write_cmd("[#{timestamp}] PROCESS_HOST_CHECK_RESULT;#{host_name};#{status_code};#{output}\n")
      end
    end
  end
end
