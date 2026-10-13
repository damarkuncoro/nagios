module Engines
  module NagiosLogReader
    def fetch_notifications(duration_seconds: 86400)
      archive_url = self.class::NAGIOS_ARCHIVE_URL
      uri = URI("#{archive_url}?query=notificationlist&starttime=-#{duration_seconds}&endtime=0")
      req = Net::HTTP::Get.new(uri)
      req.basic_auth(self.class::AUTH_USER, self.class::AUTH_PASS)

      res = Net::HTTP.start(uri.hostname, uri.port, open_timeout: 3, read_timeout: 3) { |http| http.request(req) }
      return [] unless res.is_a?(Net::HTTPSuccess)

      list = (JSON.parse(res.body).dig('data', 'notificationlist') rescue nil) || []
      return parse_local_notifications(duration_seconds) if list.empty?

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
      Rails.logger.debug("CGI notificationlist fallback: #{e.message}")
      parse_local_notifications(duration_seconds)
    end

    def parse_local_notifications(duration_seconds = 86400)
      log_path = [
        ENV['NAGIOS_LOG_FILE'],
        '/nagios_var/nagios.log',
        Rails.root.join('tmp/nagios.log').to_s
      ].compact.find { |f| File.exist?(f) }

      return [] unless log_path && File.exist?(log_path)

      now_ts = Time.now.to_i
      cutoff = now_ts - duration_seconds
      parsed = []

      File.foreach(log_path) do |line|
        if line =~ /^\[(\d+)\]\s+(SERVICE|HOST) NOTIFICATION:\s+(.+)$/
          ts = Regexp.last_match(1).to_i
          next if ts < cutoff
          type = Regexp.last_match(2)
          tokens = Regexp.last_match(3).split(';')

          if type == 'SERVICE' && tokens.size >= 5
            parsed << {
              timestamp: Time.at(ts),
              contact_name: tokens[0],
              host_name: tokens[1],
              service_desc: tokens[2],
              notification_type: tokens[3],
              state: tokens[3],
              output: tokens[4..].join(';')
            }
          elsif type == 'HOST' && tokens.size >= 4
            parsed << {
              timestamp: Time.at(ts),
              contact_name: tokens[0],
              host_name: tokens[1],
              service_desc: nil,
              notification_type: tokens[2],
              state: tokens[2],
              output: tokens[3..].join(';')
            }
          end
        end
      end

      parsed.reverse
    rescue StandardError
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
