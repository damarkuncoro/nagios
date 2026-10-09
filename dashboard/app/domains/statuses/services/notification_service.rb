require 'net/http'
require 'json'

module Statuses
  module Services
    class NotificationService
      WEBHOOK_URL = ENV['SLACK_WEBHOOK_URL']

      def self.send_alert(host_name:, service_desc:, status:, plugin_output:, target_url: nil)
        url = target_url.presence || WEBHOOK_URL
        return false if url.blank?

        color = case status.to_s.upcase
                when 'CRITICAL', 'DOWN' then '#EF4444'
                when 'WARNING' then '#F59E0B'
                else '#10B981'
                end

        payload = {
          attachments: [
            {
              color: color,
              title: "🚨 Nagios Alert: #{service_desc} on #{host_name} is #{status}",
              fields: [
                { title: "Host", value: host_name, short: true },
                { title: "Service", value: service_desc, short: true },
                { title: "Status", value: status, short: true },
                { title: "Output", value: plugin_output, short: false }
              ],
              footer: "Nagios Rails Dashboard",
              ts: Time.now.to_i
            }
          ]
        }

        uri = URI(url)
        req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
        req.body = payload.to_json

        res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') { |http| http.request(req) }
        res.is_a?(Net::HTTPSuccess)
      rescue StandardError => e
        Rails.logger.error("Gagal mengirim webhook alert: #{e.message}")
        false
      end
    end
  end
end
