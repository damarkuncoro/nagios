# frozen_string_literal: true

require 'fileutils'

module Statuses
  module Services
    # Adopts logging routines and rotation from base/logging.c
    # Formats structured Nagios log entries and rotates daemon log archives.
    class DaemonLogger
      DEFAULT_LOG_PATH = ENV.fetch('NAGIOS_LOG_FILE', '/nagios_var/nagios.log')
      DEFAULT_ARCHIVE_DIR = ENV.fetch('NAGIOS_ARCHIVE_DIR', '/nagios_var/archives')

      class << self
        # Formats and appends service alert log (base/logging.c: log_service_event)
        def log_service_event(host:, service:, state:, state_type: 'HARD', attempt: '1/1', output: '', timestamp: nil, log_path: DEFAULT_LOG_PATH)
          line = format_entry("SERVICE ALERT: #{host};#{service};#{state.to_s.upcase};#{state_type.to_s.upcase};#{attempt};#{output}", timestamp: timestamp)
          append_log(line, log_path)
          line
        end

        # Formats and appends host alert log (base/logging.c: log_host_event)
        def log_host_event(host:, state:, state_type: 'HARD', attempt: '1/1', output: '', timestamp: nil, log_path: DEFAULT_LOG_PATH)
          line = format_entry("HOST ALERT: #{host};#{state.to_s.upcase};#{state_type.to_s.upcase};#{attempt};#{output}", timestamp: timestamp)
          append_log(line, log_path)
          line
        end

        # Formats and appends notification log
        def log_notification(type:, host:, service: nil, contact:, output: '', timestamp: nil, log_path: DEFAULT_LOG_PATH)
          entry_body = if service.present?
                         "SERVICE NOTIFICATION: #{contact};#{host};#{service};#{type.to_s.upcase};#{output}"
                       else
                         "HOST NOTIFICATION: #{contact};#{host};#{type.to_s.upcase};#{output}"
                       end
          line = format_entry(entry_body, timestamp: timestamp)
          append_log(line, log_path)
          line
        end

        # Formats and appends external command execution log
        def log_command(command_str, timestamp: nil, log_path: DEFAULT_LOG_PATH)
          line = format_entry("EXTERNAL COMMAND: #{command_str}", timestamp: timestamp)
          append_log(line, log_path)
          line
        end

        # Rotates current log file to archive directory (base/logging.c: rotate_log_file)
        # Format: nagios-MM-DD-YYYY-00.log
        def rotate(log_path: DEFAULT_LOG_PATH, archive_dir: DEFAULT_ARCHIVE_DIR, timestamp: nil)
          return false unless File.exist?(log_path) && File.size(log_path).positive?

          t = timestamp || (Time.respond_to?(:current) ? Time.current : Time.now)
          date_suffix = t.strftime('%m-%d-%Y')

          FileUtils.mkdir_p(archive_dir) unless Dir.exist?(archive_dir)

          # Find next rotation counter suffix (00, 01, etc.)
          counter = 0
          archive_file = nil
          loop do
            archive_name = format('nagios-%s-%02d.log', date_suffix, counter)
            candidate = File.join(archive_dir, archive_name)
            unless File.exist?(candidate)
              archive_file = candidate
              break
            end
            counter += 1
          end

          # Atomically move log and reopen
          FileUtils.mv(log_path, archive_file)

          # Write rotation notice to new log
          log_rotation_notice = format_entry("LOG ROTATION: #{File.basename(archive_file)}", timestamp: t)
          append_log(log_rotation_notice, log_path)

          archive_file
        rescue StandardError => e
          Rails.logger.error("[DaemonLogger] Gagal rotasi log: #{e.message}")
          false
        end

        # Formats and appends general system event log
        def log_system_event(message, timestamp: nil, log_path: DEFAULT_LOG_PATH)
          line = format_entry(message, timestamp: timestamp)
          append_log(line, log_path)
          line
        end

        # Formats standard line with [epoch_timestamp] prefix
        def format_entry(message, timestamp: nil)
          ts = timestamp ? timestamp.to_i : (Time.respond_to?(:current) ? Time.current : Time.now).to_i
          "[#{ts}] #{message.to_s.strip}"
        end

        def append_log(line, path)
          return if path.to_s.strip.empty?

          dir = File.dirname(path)
          FileUtils.mkdir_p(dir) unless Dir.exist?(dir)

          File.open(path, 'a') do |f|
            f.puts(line)
          end
        rescue StandardError => e
          Rails.logger.error("[DaemonLogger] Gagal menulis log: #{e.message}") if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        end
      end
    end
  end
end
