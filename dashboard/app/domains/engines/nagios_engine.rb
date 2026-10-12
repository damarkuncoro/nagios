require 'net/http'
require 'json'

module Engines
  class NagiosEngine < Statuses::Repositories::StatusRepository
    include NagiosCommandPipe
    include NagiosLogReader

    NAGIOS_URL = ENV.fetch('NAGIOS_URL', 'http://nagios/nagios/cgi-bin/statusjson.cgi')
    NAGIOS_OBJECT_URL = ENV.fetch('NAGIOS_OBJECT_URL', 'http://nagios/nagios/cgi-bin/objectjson.cgi')
    NAGIOS_ARCHIVE_URL = ENV.fetch('NAGIOS_ARCHIVE_URL', 'http://nagios/nagios/cgi-bin/archivejson.cgi')
    NAGIOS_CMD_PIPE = ENV.fetch('NAGIOS_CMD_PIPE', '/nagios_var/rw/nagios.cmd')
    AUTH_USER = ENV.fetch('NAGIOS_AUTH_USER', 'nagiosadmin')
    AUTH_PASS = ENV.fetch('NAGIOS_AUTH_PASS', 'nagiosadmin')

    class << self
      def program_status; new.fetch_program_status; end
      def hosts; new.fetch_hosts; end
      def services; new.fetch_services; end
      def hostgroups; new.fetch_hostgroups; end
      def commands; new.fetch_commands; end
      def host_objects; new.fetch_host_objects; end
      def service_objects; new.fetch_service_objects; end
      def contacts; new.fetch_contacts; end
      def contactgroups; new.fetch_contactgroups; end
      def timeperiods; new.fetch_timeperiods; end
      def alerts(duration_seconds: 86400); new.fetch_alerts(duration_seconds: duration_seconds); end
      def downtimes; new.fetch_downtimes; end
      def comments; new.fetch_comments; end
      def notifications(duration_seconds: 86400); new.fetch_notifications(duration_seconds: duration_seconds); end
      def event_logs(limit: 200, filter_type: nil); new.fetch_event_logs(limit: limit, filter_type: filter_type); end

      def delete_comment(comment_id); new.delete_comment(comment_id); end
      def add_service_comment(h, s, a, c); new.add_service_comment(h, s, a, c); end
      def add_host_comment(h, a, c); new.add_host_comment(h, a, c); end
      def schedule_host_recheck(h); new.schedule_host_recheck(h); end
      def schedule_service_recheck(h, s); new.schedule_service_recheck(h, s); end
      def schedule_forced_host_svc_checks(h); new.schedule_forced_host_svc_checks(h); end
      def acknowledge_service_problem(h, s, a, c); new.acknowledge_service_problem(h, s, a, c); end
      def acknowledge_host_problem(h, author: 'nagiosadmin', comment: 'Acknowledged via Dashboard')
        new.acknowledge_host_problem(h, author, comment)
      end
      def remove_host_acknowledgement(h); new.remove_host_acknowledgement(h); end
      def remove_service_acknowledgement(h, s); new.remove_service_acknowledgement(h, s); end
      def schedule_service_downtime(h, s, duration_hours: 1, author: 'nagiosadmin', comment: 'Scheduled Maintenance')
        new.schedule_service_downtime(h, s, duration_hours: duration_hours, author: author, comment: comment)
      end
      def schedule_host_downtime(h, duration_hours: 1, author: 'nagiosadmin', comment: 'Scheduled Maintenance')
        new.schedule_host_downtime(h, duration_hours: duration_hours, author: author, comment: comment)
      end
      def schedule_host_and_services_downtime(h, duration_hours: 2, author: 'nagiosadmin', comment: 'Scheduled Maintenance')
        new.schedule_host_and_services_downtime(h, duration_hours: duration_hours, author: author, comment: comment)
      end
      def cancel_downtime(downtime_id); new.cancel_downtime(downtime_id); end
      def toggle_feature(feature_name, enable_flag); new.toggle_feature(feature_name, enable_flag); end
      def toggle_service_notifications(h, s, e); new.toggle_service_notifications(h, s, e); end
      def toggle_service_checks(h, s, e); new.toggle_service_checks(h, s, e); end
      def toggle_host_notifications(h, e); new.toggle_host_notifications(h, e); end
      def toggle_host_checks(h, e); new.toggle_host_checks(h, e); end
      def toggle_host_flap_detection(h, e); new.toggle_host_flap_detection(h, e); end
      def toggle_service_flap_detection(h, s, e); new.toggle_service_flap_detection(h, s, e); end
      def submit_passive_check(h, s, code, out); new.submit_passive_check(h, s, code, out); end
    end

    def fetch_program_status
      info = http_get_json("#{NAGIOS_URL}?query=programstatus")&.dig('data', 'programstatus')
      if info.nil? || info.empty?
        snap = local_snapshot
        info = snap&.programstatus || {}
      end
      return nil if info.empty?

      Statuses::Entities::EngineStatus.new(
        version: info['version'] || '4.5.14-Ruby',
        pid: info['nagios_pid'] || Process.pid,
        notifications_enabled: info['enable_notifications'] || 1,
        service_checks_enabled: info['execute_service_checks'] || 1,
        passive_service_checks_enabled: info['accept_passive_service_checks'] || 1,
        event_handlers_enabled: info['enable_event_handlers'] || 1,
        flap_detection_enabled: info['enable_flap_detection'] || 1,
        perf_data_enabled: info['process_performance_data'] || 1,
        program_start: info['program_start'] || Time.now.to_i
      ).to_h
    end

    def fetch_hosts
      data = http_get_json("#{NAGIOS_URL}?query=hostlist&details=true")&.dig('data', 'hostlist')
      if data.nil? || data.empty?
        snap = local_snapshot
        data = snap&.hosts || {}
      end

      data.map do |name, info|
        h = info.is_a?(Hash) ? info : {}
        Statuses::Entities::HostStatus.new(
          name: name, status: h['current_state'] || h['status'] || info, plugin_output: h['plugin_output'],
          last_check: h['last_check'], next_check: h['next_check'],
          current_attempt: h['current_attempt'] || 1, max_attempts: h['max_attempts'] || 1,
          acknowledged: h['problem_has_been_acknowledged'],
          notifications_enabled: h['notifications_enabled'], checks_enabled: h['checks_enabled'],
          is_flapping: h['is_flapping'],
          flap_detection_enabled: h['flap_detection_enabled'] != false,
          percent_state_change: h['percent_state_change'] || 0.0
        )
      end
    end

    def fetch_services
      data = http_get_json("#{NAGIOS_URL}?query=servicelist&details=true")&.dig('data', 'servicelist')
      if data.nil? || data.empty?
        snap = local_snapshot
        data = snap&.services || {}
      end

      list = []
      data.each do |host_name, s_hash|
        next unless s_hash.is_a?(Hash)
        s_hash.each do |description, info|
          h = info.is_a?(Hash) ? info : {}
          list << Statuses::Entities::ServiceStatus.new(
            host_name: host_name, description: description, status: h['current_state'] || h['status'] || info,
            plugin_output: h['plugin_output'], perf_data: h['perf_data'],
            last_check: h['last_check'], next_check: h['next_check'],
            state_type: h['state_type'].to_i == 1 ? 'HARD' : 'SOFT',
            attempts: "#{h['current_attempt'] || 1}/#{h['max_attempts'] || 1}",
            latency: h['latency'] || 0.0, execution_time: h['execution_time'] || 0.0,
            acknowledged: h['problem_has_been_acknowledged'],
            notifications_enabled: h['notifications_enabled'], checks_enabled: h['checks_enabled'],
            is_flapping: h['is_flapping'],
            flap_detection_enabled: h['flap_detection_enabled'] != false,
            percent_state_change: h['percent_state_change'] || 0.0
          )
        end
      end
      list
    end

    def fetch_hostgroups
      groups_data = http_get_json("#{NAGIOS_OBJECT_URL}?query=hostgrouplist&details=true")&.dig('data', 'hostgrouplist') || {}
      all_hosts = fetch_hosts
      hosts_by_name = all_hosts.index_by(&:name)
      return [] unless groups_data.is_a?(Hash)

      groups_data.map do |group_name, group_info|
        h = group_info.is_a?(Hash) ? group_info : {}
        members = h['members'] || []
        member_hosts = members.map { |m| hosts_by_name[m] }.compact
        member_hosts = all_hosts if member_hosts.empty? && members.empty?
        { name: group_name, alias: h['alias'].presence || group_name, hosts: member_hosts }
      end
    end

    def fetch_commands
      data = http_get_json("#{NAGIOS_OBJECT_URL}?query=commandlist&details=true")&.dig('data', 'commandlist') || {}
      if data.is_a?(Hash)
        data.map { |name, info| info.is_a?(Hash) ? info : { 'name' => name, 'command_line' => '' } }
      elsif data.is_a?(Array)
        data.map { |c| { 'name' => c, 'command_line' => '' } }
      else
        []
      end
    end

    def fetch_contacts
      data = http_get_json("#{NAGIOS_OBJECT_URL}?query=contactlist&details=true")&.dig('data', 'contactlist') || {}
      if data.is_a?(Hash)
        data.map { |name, info| info.is_a?(Hash) ? info : { 'name' => name, 'alias' => '', 'email' => '' } }
      elsif data.is_a?(Array)
        data.map { |c| { 'name' => c, 'alias' => '', 'email' => '' } }
      else
        []
      end
    end

    def fetch_contactgroups
      data = http_get_json("#{NAGIOS_OBJECT_URL}?query=contactgrouplist&details=true")&.dig('data', 'contactgrouplist') || {}
      return [] unless data.is_a?(Hash)
      data.map { |name, info| info.is_a?(Hash) ? info : { 'group_name' => name, 'alias' => name, 'members' => [] } }
    end

    def fetch_timeperiods
      data = http_get_json("#{NAGIOS_OBJECT_URL}?query=timeperiodlist&details=true")&.dig('data', 'timeperiodlist') || {}
      if data.is_a?(Hash)
        data.map { |name, info| info.is_a?(Hash) ? info : { 'name' => name, 'alias' => name } }
      elsif data.is_a?(Array)
        data.map { |tp| { 'name' => tp, 'alias' => tp } }
      else
        []
      end
    end

    def fetch_host_objects
      http_get_json("#{NAGIOS_OBJECT_URL}?query=hostlist&details=true")&.dig('data', 'hostlist') || {}
    end

    def fetch_service_objects
      http_get_json("#{NAGIOS_OBJECT_URL}?query=servicelist&details=true")&.dig('data', 'servicelist') || {}
    end

    def fetch_alerts(duration_seconds: 86400)
      list = http_get_json("#{NAGIOS_ARCHIVE_URL}?query=alertlist&starttime=-#{duration_seconds}&endtime=0")&.dig('data', 'alertlist') || []
      list.map do |item|
        state_str = case item['state']
                    when 0 then 'OK'
                    when 1 then 'WARNING'
                    when 2 then 'CRITICAL'
                    when 3 then 'UNKNOWN'
                    else item['state'].to_s
                    end
        {
          timestamp: Time.at(item['timestamp'].to_i / 1000),
          host_name: item['host_name'],
          service_description: item['service_description'],
          state: state_str,
          plugin_output: item['plugin_output']
        }
      end
    end

    def fetch_downtimes
      data = http_get_json("#{NAGIOS_URL}?query=downtimelist&details=true")&.dig('data', 'downtimelist') || {}
      list = []
      data.each do |id, info|
        next unless info.is_a?(Hash)
        list << {
          id: id, host_name: info['host_name'], service_description: info['service_description'],
          author: info['author'], comment: info['comment'],
          start_time: Time.at(info['start_time'].to_i / 1000), end_time: Time.at(info['end_time'].to_i / 1000)
        }
      end
      list
    end

    def fetch_comments
      data = http_get_json("#{NAGIOS_URL}?query=commentlist&details=true")&.dig('data', 'commentlist') || {}
      list = []
      data.each do |id, info|
        next unless info.is_a?(Hash)
        list << {
          id: id, host_name: info['host_name'], service_description: info['service_description'],
          author: info['author'], comment: info['comment_data'],
          entry_time: Time.at(info['entry_time'].to_i / 1000)
        }
      end
      list
    end

    private

    def http_get_json(url_string)
      uri = URI(url_string)
      req = Net::HTTP::Get.new(uri)
      req.basic_auth(AUTH_USER, AUTH_PASS)
      res = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 3, read_timeout: 3) { |http| http.request(req) }
      res.is_a?(Net::HTTPSuccess) ? JSON.parse(res.body) : nil
    rescue StandardError => e
      Rails.logger.debug("HTTP GET fallback to local [#{url_string}]: #{e.message}")
      nil
    end

    def local_snapshot
      candidates = [
        ENV['NAGIOS_STATUS_FILE'],
        '/nagios_var/status.dat',
        Rails.root.join('tmp/status.dat').to_s
      ].compact

      path = candidates.find { |f| File.exist?(f) }
      return nil unless path

      Statuses::Services::StatusDataParser.parse_file(path)
    end
  end
end
