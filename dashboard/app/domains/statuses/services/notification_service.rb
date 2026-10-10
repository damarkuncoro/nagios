# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require 'time'

module Statuses
  module Services
    # Multi-channel webhook notification dispatcher supporting Slack, Discord, and Generic JSON endpoints.
    # Integrates with NotificationViability for alert suppression.
    class NotificationService
      WEBHOOK_URL = ENV['SLACK_WEBHOOK_URL']

      DeliveryResult = Struct.new(:success, :platform, :status_code, :error, keyword_init: true) do
        def success?
          success == true
        end
      end

      COLOR_HEX = {
        'CRITICAL' => '#EF4444',
        'DOWN' => '#EF4444',
        'WARNING' => '#F59E0B',
        'UNKNOWN' => '#8B5CF6',
        'OK' => '#10B981',
        'UP' => '#10B981'
      }.freeze

      COLOR_INT = {
        'CRITICAL' => 0xEF4444,
        'DOWN' => 0xEF4444,
        'WARNING' => 0xF59E0B,
        'UNKNOWN' => 0x8B5CF6,
        'OK' => 0x10B981,
        'UP' => 0x10B981
      }.freeze

      class << self
        def send_alert(host_name:, service_desc:, status:, plugin_output:, target_url: nil)
          deliver_alert(
            host_name: host_name,
            service_desc: service_desc,
            status: status,
            plugin_output: plugin_output,
            target_url: target_url
          ).success?
        end

        def deliver_alert(host_name:, service_desc:, status:, plugin_output:, target_url: nil, host_obj: nil, service_obj: nil, check_viability: false)
          url = (target_url.nil? || target_url.to_s.strip.empty?) ? (defined?(WEBHOOK_URL) ? WEBHOOK_URL : nil) : target_url.to_s.strip
          return DeliveryResult.new(success: false, platform: :unknown, error: 'Webhook URL is missing') if url.nil? || url.empty?

          platform = detect_platform(url)

          # Check viability suppression if requested
          if check_viability && (host_obj || service_obj)
            target = service_obj || host_obj
            res = NotificationViability.check(target, host: host_obj)
            unless res.viable?
              return DeliveryResult.new(success: false, platform: platform, error: "Notification suppressed: #{res.reason}")
            end
          end

          payload = build_payload(platform, host_name, service_desc, status, plugin_output)

          uri = URI(url)
          req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json')
          req.body = payload.to_json

          res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 5, read_timeout: 5) do |http|
            http.request(req)
          end

          success = res.is_a?(Net::HTTPSuccess) || res.code.to_i == 204 # Discord returns 204 No Content
          DeliveryResult.new(
            success: success,
            platform: platform,
            status_code: res.code.to_i,
            error: success ? nil : "HTTP #{res.code}: #{res.body}"
          )
        rescue StandardError => e
          Rails.logger.error("Gagal mengirim webhook alert: #{e.message}") if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
          DeliveryResult.new(success: false, platform: platform || :unknown, error: e.message)
        end

        def detect_platform(url)
          u = url.to_s.downcase
          if u.include?('discord.com/api/webhooks') || u.include?('discordapp.com/api/webhooks')
            :discord
          elsif u.include?('hooks.slack.com')
            :slack
          else
            :generic
          end
        end

        def build_payload(platform, host_name, service_desc, status, plugin_output)
          st = status.to_s.upcase
          case platform
          when :discord
            build_discord_payload(host_name, service_desc, st, plugin_output)
          when :slack
            build_slack_payload(host_name, service_desc, st, plugin_output)
          else
            build_generic_payload(host_name, service_desc, st, plugin_output)
          end
        end

        private

        def build_slack_payload(host_name, service_desc, status, plugin_output)
          color = COLOR_HEX[status] || '#6B7280'
          title = service_desc ? "🚨 Nagios Alert: #{service_desc} on #{host_name} is #{status}" : "🚨 Nagios Host Alert: #{host_name} is #{status}"
          fields = [
            { title: 'Host', value: host_name.to_s, short: true },
            { title: 'Status', value: status, short: true }
          ]
          fields.insert(1, { title: 'Service', value: service_desc.to_s, short: true }) if service_desc

          fields << { title: 'Output', value: plugin_output.to_s, short: false }

          {
            attachments: [
              {
                color: color,
                title: title,
                fields: fields,
                footer: 'Nagios Rails Dashboard',
                ts: Time.now.to_i
              }
            ]
          }
        end

        def build_discord_payload(host_name, service_desc, status, plugin_output)
          color = COLOR_INT[status] || 0x6B7280
          title = service_desc ? "🚨 Nagios Alert: #{service_desc} on #{host_name} is #{status}" : "🚨 Nagios Host Alert: #{host_name} is #{status}"
          fields = [
            { name: 'Host', value: host_name.to_s, inline: true },
            { name: 'Status', value: status, inline: true }
          ]
          fields.insert(1, { name: 'Service', value: service_desc.to_s, inline: true }) if service_desc

          fields << { name: 'Output', value: plugin_output.to_s, inline: false }

          {
            embeds: [
              {
                title: title,
                color: color,
                fields: fields,
                footer: { text: 'Nagios Rails Dashboard' },
                timestamp: Time.now.utc.strftime('%Y-%m-%dT%H:%M:%SZ')
              }
            ]
          }
        end

        def build_generic_payload(host_name, service_desc, status, plugin_output)
          {
            event: 'nagios_alert',
            host_name: host_name.to_s,
            service_desc: service_desc,
            status: status,
            plugin_output: plugin_output.to_s,
            timestamp: Time.now.to_i,
            dashboard_source: 'Nagios Core Modern Dashboard'
          }
        end
      end
    end
  end
end
