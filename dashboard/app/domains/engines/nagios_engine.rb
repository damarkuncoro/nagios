require 'net/http'
require 'json'

module Engines
  class NagiosEngine < Statuses::Repositories::StatusRepository
    NAGIOS_URL = ENV.fetch('NAGIOS_URL', 'http://nagios/nagios/cgi-bin/statusjson.cgi')
    NAGIOS_OBJECT_URL = ENV.fetch('NAGIOS_OBJECT_URL', 'http://nagios/nagios/cgi-bin/objectjson.cgi')
    NAGIOS_ARCHIVE_URL = ENV.fetch('NAGIOS_ARCHIVE_URL', 'http://nagios/nagios/cgi-bin/archivejson.cgi')
    NAGIOS_CMD_PIPE = ENV.fetch('NAGIOS_CMD_PIPE', '/nagios_var/rw/nagios.cmd')
    AUTH_USER = ENV.fetch('NAGIOS_AUTH_USER', 'nagiosadmin')
    AUTH_PASS = ENV.fetch('NAGIOS_AUTH_PASS', 'nagiosadmin')

    def self.program_status
      new.fetch_program_status
    end

    def self.hosts
      new.fetch_hosts
    end

    def self.services
      new.fetch_services
    end

    def self.hostgroups
      new.fetch_hostgroups
    end

    def self.commands
      new.fetch_commands
    end

    def self.contacts
      new.fetch_contacts
    end

    def self.timeperiods
      new.fetch_timeperiods
    end

    def self.alerts(duration_seconds: 86400)
      new.fetch_alerts(duration_seconds: duration_seconds)
    end

    def self.downtimes
      new.fetch_downtimes
    end

    def self.comments
      new.fetch_comments
    end

    def self.delete_comment(comment_id)
      new.delete_comment(comment_id)
    end

    def self.add_service_comment(host_name, service_desc, author, comment)
      new.add_service_comment(host_name, service_desc, author, comment)
    end

    def self.schedule_host_recheck(host_name)
      new.schedule_host_recheck(host_name)
    end

    def self.schedule_service_recheck(host_name, service_desc)
      new.schedule_service_recheck(host_name, service_desc)
    end

    def self.acknowledge_service_problem(host_name, service_desc, author, comment)
      new.acknowledge_service_problem(host_name, service_desc, author, comment)
    end

    def self.schedule_service_downtime(host_name, service_desc, duration_hours: 1, author: 'nagiosadmin', comment: 'Scheduled Maintenance')
      new.schedule_service_downtime(host_name, service_desc, duration_hours: duration_hours, author: author, comment: comment)
    end

    def self.cancel_downtime(downtime_id)
      new.cancel_downtime(downtime_id)
    end

    def self.toggle_feature(feature_name, enable_flag)
      new.toggle_feature(feature_name, enable_flag)
    end

    def fetch_program_status
      uri = URI("#{NAGIOS_URL}?query=programstatus")
      req = Net::HTTP::Get.new(uri)
      req.basic_auth(AUTH_USER, AUTH_PASS)

      res = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 3, read_timeout: 3) { |http| http.request(req) }
      return nil unless res.is_a?(Net::HTTPSuccess)

      info = JSON.parse(res.body).dig('data', 'programstatus') || {}
      Statuses::Entities::EngineStatus.new(
        version: info['version'] || '4.x',
        pid: info['nagios_pid'],
        notifications_enabled: info['enable_notifications'],
        service_checks_enabled: info['execute_service_checks'],
        passive_service_checks_enabled: info['accept_passive_service_checks'],
        event_handlers_enabled: info['enable_event_handlers'],
        flap_detection_enabled: info['enable_flap_detection'],
        perf_data_enabled: info['process_performance_data'],
        program_start: info['program_start']
      ).to_h
    rescue StandardError => e
      Rails.logger.error("Gagal koneksi programstatus: #{e.message}")
      nil
    end

    def fetch_hosts
      uri = URI("#{NAGIOS_URL}?query=hostlist&details=true")
      req = Net::HTTP::Get.new(uri)
      req.basic_auth(AUTH_USER, AUTH_PASS)

      res = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 3, read_timeout: 3) { |http| http.request(req) }
      return [] unless res.is_a?(Net::HTTPSuccess)

      data = JSON.parse(res.body).dig('data', 'hostlist') || {}

      data.map do |name, info|
        info_hash = info.is_a?(Hash) ? info : {}
        Statuses::Entities::HostStatus.new(
          name: name,
          status: info_hash['status'] || info,
          plugin_output: info_hash['plugin_output'],
          last_check: info_hash['last_check'],
          next_check: info_hash['next_check'],
          current_attempt: info_hash['current_attempt'] || 1,
          max_attempts: info_hash['max_attempts'] || 1,
          acknowledged: info_hash['problem_has_been_acknowledged']
        )
      end
    rescue StandardError => e
      Rails.logger.error("Gagal fetch hosts domain: #{e.message}")
      []
    end

    def fetch_services
      uri = URI("#{NAGIOS_URL}?query=servicelist&details=true")
      req = Net::HTTP::Get.new(uri)
      req.basic_auth(AUTH_USER, AUTH_PASS)

      res = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 3, read_timeout: 3) { |http| http.request(req) }
      return [] unless res.is_a?(Net::HTTPSuccess)

      data = JSON.parse(res.body).dig('data', 'servicelist') || {}
      services_list = []

      data.each do |host_name, service_hash|
        next unless service_hash.is_a?(Hash)

        service_hash.each do |description, info|
          info_hash = info.is_a?(Hash) ? info : {}
          state_type_str = info_hash['state_type'] == 1 ? 'HARD' : 'SOFT'
          attempts_str = "#{info_hash['current_attempt'] || 1}/#{info_hash['max_attempts'] || 1}"

          services_list << Statuses::Entities::ServiceStatus.new(
            host_name: host_name,
            description: description,
            status: info_hash['status'] || info,
            plugin_output: info_hash['plugin_output'],
            perf_data: info_hash['perf_data'],
            last_check: info_hash['last_check'],
            next_check: info_hash['next_check'],
            state_type: state_type_str,
            attempts: attempts_str,
            latency: info_hash['latency'] || 0.0,
            execution_time: info_hash['execution_time'] || 0.0,
            acknowledged: info_hash['problem_has_been_acknowledged']
          )
        end
      end

      services_list
    rescue StandardError => e
      Rails.logger.error("Gagal fetch services domain: #{e.message}")
      []
    end

    def fetch_hostgroups
      uri = URI("#{NAGIOS_OBJECT_URL}?query=hostgrouplist")
      req = Net::HTTP::Get.new(uri)
      req.basic_auth(AUTH_USER, AUTH_PASS)

      res = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 3, read_timeout: 3) { |http| http.request(req) }
      return [] unless res.is_a?(Net::HTTPSuccess)

      groups = JSON.parse(res.body).dig('data', 'hostgrouplist') || []
      all_hosts = fetch_hosts

      groups.map do |group_name|
        {
          name: group_name,
          hosts: all_hosts
        }
      end
    rescue StandardError => e
      Rails.logger.error("Gagal fetch hostgroups: #{e.message}")
      []
    end

    def fetch_commands
      uri = URI("#{NAGIOS_OBJECT_URL}?query=commandlist")
      req = Net::HTTP::Get.new(uri)
      req.basic_auth(AUTH_USER, AUTH_PASS)

      res = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 3, read_timeout: 3) { |http| http.request(req) }
      return [] unless res.is_a?(Net::HTTPSuccess)

      JSON.parse(res.body).dig('data', 'commandlist') || []
    rescue StandardError => e
      Rails.logger.error("Gagal fetch commandlist: #{e.message}")
      []
    end

    def fetch_contacts
      uri = URI("#{NAGIOS_OBJECT_URL}?query=contactlist")
      req = Net::HTTP::Get.new(uri)
      req.basic_auth(AUTH_USER, AUTH_PASS)

      res = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 3, read_timeout: 3) { |http| http.request(req) }
      return [] unless res.is_a?(Net::HTTPSuccess)

      JSON.parse(res.body).dig('data', 'contactlist') || []
    rescue StandardError => e
      Rails.logger.error("Gagal fetch contactlist: #{e.message}")
      []
    end

    def fetch_timeperiods
      uri = URI("#{NAGIOS_OBJECT_URL}?query=timeperiodlist")
      req = Net::HTTP::Get.new(uri)
      req.basic_auth(AUTH_USER, AUTH_PASS)

      res = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 3, read_timeout: 3) { |http| http.request(req) }
      return [] unless res.is_a?(Net::HTTPSuccess)

      JSON.parse(res.body).dig('data', 'timeperiodlist') || []
    rescue StandardError => e
      Rails.logger.error("Gagal fetch timeperiodlist: #{e.message}")
      []
    end

    def fetch_alerts(duration_seconds: 86400)
      endtime = Time.now.to_i
      starttime = endtime - duration_seconds.to_i

      uri = URI("#{NAGIOS_ARCHIVE_URL}?query=alertlist&starttime=-#{duration_seconds}&endtime=0")
      req = Net::HTTP::Get.new(uri)
      req.basic_auth(AUTH_USER, AUTH_PASS)

      res = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 3, read_timeout: 3) { |http| http.request(req) }
      return [] unless res.is_a?(Net::HTTPSuccess)

      alerts = JSON.parse(res.body).dig('data', 'alertlist') || []
      alerts.map do |item|
        {
          timestamp: Time.at(item['timestamp'].to_i / 1000),
          host_name: item['host_name'],
          service_description: item['service_description'],
          state: item['state'],
          plugin_output: item['plugin_output']
        }
      end
    rescue StandardError => e
      Rails.logger.error("Gagal fetch alerts: #{e.message}")
      []
    end

    def fetch_downtimes
      uri = URI("#{NAGIOS_URL}?query=downtimelist&details=true")
      req = Net::HTTP::Get.new(uri)
      req.basic_auth(AUTH_USER, AUTH_PASS)

      res = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 3, read_timeout: 3) { |http| http.request(req) }
      return [] unless res.is_a?(Net::HTTPSuccess)

      data = JSON.parse(res.body).dig('data', 'downtimelist') || {}
      downtimes_list = []

      data.each do |id, info|
        next unless info.is_a?(Hash)
        downtimes_list << {
          id: id,
          host_name: info['host_name'],
          service_description: info['service_description'],
          author: info['author'],
          comment: info['comment'],
          start_time: Time.at(info['start_time'].to_i / 1000),
          end_time: Time.at(info['end_time'].to_i / 1000)
        }
      end

      downtimes_list
    rescue StandardError => e
      Rails.logger.error("Gagal fetch downtimes: #{e.message}")
      []
    end

    def fetch_comments
      uri = URI("#{NAGIOS_URL}?query=commentlist&details=true")
      req = Net::HTTP::Get.new(uri)
      req.basic_auth(AUTH_USER, AUTH_PASS)

      res = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 3, read_timeout: 3) { |http| http.request(req) }
      return [] unless res.is_a?(Net::HTTPSuccess)

      data = JSON.parse(res.body).dig('data', 'commentlist') || {}
      comments_list = []

      data.each do |id, info|
        next unless info.is_a?(Hash)
        comments_list << {
          id: id,
          host_name: info['host_name'],
          service_description: info['service_description'],
          author: info['author'],
          comment: info['comment_data'],
          entry_time: Time.at(info['entry_time'].to_i / 1000)
        }
      end

      comments_list
    rescue StandardError => e
      Rails.logger.error("Gagal fetch comments: #{e.message}")
      []
    end

    def delete_comment(comment_id)
      timestamp = Time.now.to_i
      command = "[#{timestamp}] DEL_SVC_COMMENT;#{comment_id}\n"
      write_cmd(command)
    end

    def add_service_comment(host_name, service_desc, author, comment)
      timestamp = Time.now.to_i
      command = "[#{timestamp}] ADD_SVC_COMMENT;#{host_name};#{service_desc};1;#{author};#{comment}\n"
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

    def schedule_service_downtime(host_name, service_desc, duration_hours: 1, author: 'nagiosadmin', comment: 'Scheduled Maintenance')
      start_time = Time.now.to_i
      end_time = start_time + (duration_hours.to_i * 3600)
      duration = duration_hours.to_i * 3600
      command = "[#{start_time}] SCHEDULE_SVC_DOWNTIME;#{host_name};#{service_desc};#{start_time};#{end_time};1;0;#{duration};#{author};#{comment}\n"
      write_cmd(command)
    end

    def cancel_downtime(downtime_id)
      timestamp = Time.now.to_i
      command = "[#{timestamp}] DEL_SVC_DOWNTIME;#{downtime_id}\n"
      write_cmd(command)
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

    private

    def write_cmd(command)
      if File.exist?(NAGIOS_CMD_PIPE)
        File.open(NAGIOS_CMD_PIPE, 'a') { |f| f.write(command) }
        true
      else
        Rails.logger.error("Nagios FIFO pipe tidak ditemukan di #{NAGIOS_CMD_PIPE}")
        false
      end
    end
  end
end
