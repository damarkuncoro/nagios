module Engines
  module NagiosLogReader
    def fetch_notifications(duration_seconds: 86400)
      archive_url = self.class::NAGIOS_ARCHIVE_URL
      uri = URI("#{archive_url}?query=notificationlist&starttime=-#{duration_seconds}&endtime=0")
      req = Net::HTTP::Get.new(uri)
      req.basic_auth(self.class::AUTH_USER, self.class::AUTH_PASS)

      res = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 3, read_timeout: 3) { |http| http.request(req) }
      return [] unless res.is_a?(Net::HTTPSuccess)

      list = JSON.parse(res.body).dig('data', 'notificationlist') || []
      list.map do |notif|
        {
          timestamp: Time.at((notif['timestamp'] || 0) / 1000),
          host_name: notif['host_name'],
          service_desc: notif['service_description'],
          contact_name: notif['contact_name'],
          notification_type: notif['notification_type'],
          state: notif['state'],
          output: notif['output']
        }
      end
    rescue StandardError => e
      Rails.logger.error("Gagal fetch notificationlist: #{e.message}")
      []
    end

    def fetch_event_logs(limit: 200, filter_type: nil)
      log_path = ENV.fetch('NAGIOS_LOG_FILE', '/nagios_var/nagios.log')
      return [] unless File.exist?(log_path)

      lines = File.readlines(log_path).last(1000).reverse
      logs = []

      lines.each do |line|
        match = line.match(/^\[(\d+)\]\s+([A-Z\s_]+?):\s+(.*)$/)
        if match
          ts = Time.at(match[1].to_i)
          type = match[2].strip
          details = match[3].strip

          category = case type
                     when /ALERT/
                       'ALERT'
                     when /NOTIFICATION/
                       'NOTIFICATION'
                     when /EXTERNAL COMMAND/
                       'COMMAND'
                     else
                       'SYSTEM'
                     end

          next if filter_type.present? && filter_type != 'ALL' && category != filter_type

          logs << {
            timestamp: ts,
            type: type,
            category: category,
            message: details,
            raw: line.strip
          }
        else
          ts_match = line.match(/^\[(\d+)\]\s+(.*)$/)
          if ts_match
            ts = Time.at(ts_match[1].to_i)
            category = 'SYSTEM'
            next if filter_type.present? && filter_type != 'ALL' && category != filter_type

            logs << {
              timestamp: ts,
              type: 'INFO',
              category: category,
              message: ts_match[2].strip,
              raw: line.strip
            }
          end
        end

        break if logs.size >= limit
      end

      logs
    rescue StandardError => e
      Rails.logger.error("Gagal membaca nagios.log: #{e.message}")
      []
    end
  end
end
