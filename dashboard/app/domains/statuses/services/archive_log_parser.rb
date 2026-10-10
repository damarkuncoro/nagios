# frozen_string_literal: true

module Statuses
  module Services
    # Adopts historical archive log parsing and event extraction from
    # cgi/archiveutils.c and cgi/showlog.c
    # Parses `nagios.log` and rotated archives (`var/archives/nagios-MM-DD-YYYY-00.log`),
    # decomposing entries into structured alert, notification, downtime, and flapping events.
    class ArchiveLogParser
      LogEntry = Struct.new(
        :timestamp,
        :category,
        :event_type,
        :host_name,
        :service_desc,
        :state,
        :state_type,
        :attempt,
        :contact_name,
        :message,
        :raw,
        keyword_init: true
      ) do
        def alert?
          category == :alert
        end

        def notification?
          category == :notification
        end

        def downtime?
          category == :downtime
        end

        def flapping?
          category == :flapping
        end

        def hard_state?
          state_type == 'HARD'
        end

        def soft_state?
          state_type == 'SOFT'
        end
      end

      class << self
        def parse_line(raw_line)
          new.parse_line(raw_line)
        end

        def parse(content, filter: {})
          new.parse(content, filter: filter)
        end

        def parse_file(file_path, filter: {})
          return [] unless File.exist?(file_path)

          new.parse(File.read(file_path), filter: filter)
        end

        def parse_archives(archives_dir, current_log_path: nil, filter: {})
          new.parse_archives(archives_dir, current_log_path: current_log_path, filter: filter)
        end
      end

      # Parses full log content (cgi/showlog.c & cgi/archiveutils.c)
      def parse(content, filter: {})
        return [] if content.nil? || content.to_s.strip.empty?

        entries = []
        content.each_line do |line|
          entry = parse_line(line)
          next unless entry
          next unless match_filter?(entry, filter)

          entries << entry
        end
        entries
      end

      # Parses individual Nagios log line (cgi/archiveutils.c: parse_archive_log_entry)
      def parse_line(raw_line)
        line = raw_line.to_s.strip
        return nil if line.empty? || line.start_with?('#')

        match = line.match(/\A\[(\d+)\]\s+(?:([A-Z\s_]+?):\s+)?(.*)\z/)
        return nil unless match

        ts = Time.at(match[1].to_i)
        prefix = match[2].to_s.strip
        details = match[3].to_s.strip

        if prefix.empty?
          # General system/kernel line e.g. [1700000000] Nagios Core starting...
          return LogEntry.new(
            timestamp: ts,
            category: :system,
            event_type: 'SYSTEM',
            host_name: nil,
            service_desc: nil,
            state: nil,
            state_type: nil,
            attempt: nil,
            contact_name: nil,
            message: details,
            raw: line
          )
        end

        parse_typed_entry(ts, prefix, details, line)
      end

      # Reads and combines historical archive logs in chronological order
      def parse_archives(archives_dir, current_log_path: nil, filter: {})
        entries = []

        # 1. Read rotated archives sorted by filename date
        if Dir.exist?(archives_dir.to_s)
          archive_files = Dir.glob(File.join(archives_dir, 'nagios-*.log')).sort
          archive_files.each do |f|
            entries.concat(parse_file(f, filter: filter))
          end
        end

        # 2. Read active log file
        if current_log_path && File.exist?(current_log_path)
          entries.concat(parse_file(current_log_path, filter: filter))
        end

        entries
      end

      private

      def parse_typed_entry(ts, prefix, details, raw_line)
        case prefix
        when 'SERVICE ALERT'
          # host;service;state;state_type;attempt;output
          parts = details.split(';', 6)
          LogEntry.new(
            timestamp: ts,
            category: :alert,
            event_type: 'SERVICE_ALERT',
            host_name: parts[0],
            service_desc: parts[1],
            state: parts[2],
            state_type: parts[3],
            attempt: parts[4].to_i,
            contact_name: nil,
            message: parts[5],
            raw: raw_line
          )
        when 'HOST ALERT'
          # host;state;state_type;attempt;output
          parts = details.split(';', 5)
          LogEntry.new(
            timestamp: ts,
            category: :alert,
            event_type: 'HOST_ALERT',
            host_name: parts[0],
            service_desc: nil,
            state: parts[1],
            state_type: parts[2],
            attempt: parts[3].to_i,
            contact_name: nil,
            message: parts[4],
            raw: raw_line
          )
        when 'SERVICE NOTIFICATION'
          # contact;host;service;state;command;output
          parts = details.split(';', 6)
          LogEntry.new(
            timestamp: ts,
            category: :notification,
            event_type: 'SERVICE_NOTIFICATION',
            host_name: parts[1],
            service_desc: parts[2],
            state: parts[3],
            state_type: nil,
            attempt: nil,
            contact_name: parts[0],
            message: parts[5],
            raw: raw_line
          )
        when 'HOST NOTIFICATION'
          # contact;host;state;command;output
          parts = details.split(';', 5)
          LogEntry.new(
            timestamp: ts,
            category: :notification,
            event_type: 'HOST_NOTIFICATION',
            host_name: parts[1],
            service_desc: nil,
            state: parts[2],
            state_type: nil,
            attempt: nil,
            contact_name: parts[0],
            message: parts[4],
            raw: raw_line
          )
        when 'SERVICE DOWNTIME ALERT'
          # host;service;action;comment
          parts = details.split(';', 4)
          LogEntry.new(
            timestamp: ts,
            category: :downtime,
            event_type: "SERVICE_DOWNTIME_#{parts[2]}",
            host_name: parts[0],
            service_desc: parts[1],
            state: parts[2],
            state_type: nil,
            attempt: nil,
            contact_name: nil,
            message: parts[3],
            raw: raw_line
          )
        when 'HOST DOWNTIME ALERT'
          # host;action;comment
          parts = details.split(';', 3)
          LogEntry.new(
            timestamp: ts,
            category: :downtime,
            event_type: "HOST_DOWNTIME_#{parts[1]}",
            host_name: parts[0],
            service_desc: nil,
            state: parts[1],
            state_type: nil,
            attempt: nil,
            contact_name: nil,
            message: parts[2],
            raw: raw_line
          )
        when 'SERVICE FLAPPING ALERT'
          # host;service;action;comment
          parts = details.split(';', 4)
          LogEntry.new(
            timestamp: ts,
            category: :flapping,
            event_type: "SERVICE_FLAPPING_#{parts[2]}",
            host_name: parts[0],
            service_desc: parts[1],
            state: parts[2],
            state_type: nil,
            attempt: nil,
            contact_name: nil,
            message: parts[3],
            raw: raw_line
          )
        when 'HOST FLAPPING ALERT'
          # host;action;comment
          parts = details.split(';', 3)
          LogEntry.new(
            timestamp: ts,
            category: :flapping,
            event_type: "HOST_FLAPPING_#{parts[1]}",
            host_name: parts[0],
            service_desc: nil,
            state: parts[1],
            state_type: nil,
            attempt: nil,
            contact_name: nil,
            message: parts[2],
            raw: raw_line
          )
        when 'EXTERNAL COMMAND'
          LogEntry.new(
            timestamp: ts,
            category: :command,
            event_type: 'EXTERNAL_COMMAND',
            host_name: nil,
            service_desc: nil,
            state: nil,
            state_type: nil,
            attempt: nil,
            contact_name: nil,
            message: details,
            raw: raw_line
          )
        else
          LogEntry.new(
            timestamp: ts,
            category: :system,
            event_type: prefix,
            host_name: nil,
            service_desc: nil,
            state: nil,
            state_type: nil,
            attempt: nil,
            contact_name: nil,
            message: details,
            raw: raw_line
          )
        end
      end

      def match_filter?(entry, filter)
        return true if filter.empty?

        if filter[:category] && entry.category != filter[:category].to_sym
          return false
        end

        if filter[:host_name] && entry.host_name != filter[:host_name]
          return false
        end

        if filter[:service_desc] && entry.service_desc != filter[:service_desc]
          return false
        end

        if filter[:start_time] && entry.timestamp < filter[:start_time]
          return false
        end

        if filter[:end_time] && entry.timestamp > filter[:end_time]
          return false
        end

        if filter[:state_type] && entry.state_type != filter[:state_type].to_s.upcase
          return false
        end

        true
      end
    end
  end
end
