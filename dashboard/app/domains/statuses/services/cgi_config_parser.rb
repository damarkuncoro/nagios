# frozen_string_literal: true

require 'time'

module Statuses
  module Services
    # Adopts CGI configuration file parsing and CGI utility formatting from cgi/cgiutils.c
    # Parses, validates, and serializes cgi.cfg directives, provides contact authorization mappings,
    # and implements human interval formatting and plugin output sanitization.
    class CgiConfigParser
      BOOLEAN_DIRECTIVES = %w[
        use_authentication
        use_ssl_authentication
        show_context_help
        use_pending_states
        enable_page_tour
        escape_html_tags
        lock_author_names
      ].freeze

      INTEGER_DIRECTIVES = %w[
        refresh_rate
        result_limit
        default_statusmap_layout
        default_statuswrl_layout
      ].freeze

      CONTACT_LIST_DIRECTIVES = %w[
        authorized_for_system_information
        authorized_for_configuration_information
        authorized_for_system_commands
        authorized_for_all_services
        authorized_for_all_hosts
        authorized_for_all_service_commands
        authorized_for_all_host_commands
        authorized_for_read_only
      ].freeze

      DEFAULT_REFRESH_RATE = 90
      DEFAULT_RESULT_LIMIT = 50

      attr_reader :directives, :raw_lines

      class << self
        def parse(content)
          new.parse(content)
        end

        def read(file_path)
          new.read(file_path)
        end

        # Formats interval in seconds into human interval string e.g. "1d 2h 30m 15s"
        # (cgi/cgiutils.c: get_interval_time_string)
        def format_interval(seconds)
          sec = seconds.to_i.abs
          days = sec / 86_400
          hours = (sec % 86_400) / 3600
          minutes = (sec % 3600) / 60
          secs = sec % 60

          "#{days}d #{hours}h #{minutes}m #{secs}s"
        end

        # Formats time into standard Nagios date format (cgi/cgiutils.c: get_time_string)
        def format_date(time_val, format: :iso8601)
          t = to_time(time_val)
          return '' if t.nil?

          case format.to_sym
          when :us
            t.strftime('%m-%d-%Y %H:%M:%S')
          when :euro
            t.strftime('%d-%m-%Y %H:%M:%S')
          when :http
            t.strftime('%a, %d %b %Y %H:%M:%S GMT')
          else # :iso8601
            t.strftime('%Y-%m-%d %H:%M:%S')
          end
        end

        # Sanitizes plugin output (cgi/cgiutils.c: sanitize_plugin_output)
        def sanitize_output(raw_str)
          return '' if raw_str.nil?

          s = raw_str.to_s
          # Unescape literal newlines
          s = s.gsub('\\n', "\n")
          # Strip harmful script/style tags while preserving text
          s.gsub(%r{<\s*(script|style)[^>]*>.*?<\s*/\s*\1\s*>}im, '')
        end

        private

        def to_time(val)
          case val
          when Time then val
          when Numeric then val.to_i <= 0 ? nil : Time.at(val.to_i)
          when String
            begin
              Time.parse(val)
            rescue StandardError
              nil
            end
          end
        end
      end

      def initialize
        @directives = {}
        @raw_lines = []
      end

      # Reads and parses cgi.cfg from disk (cgi/cgiutils.c: read_cgi_config_file)
      def read(file_path)
        return self unless File.exist?(file_path)

        content = File.read(file_path)
        parse(content)
      end

      # Parses cgi.cfg text content
      def parse(content)
        @directives = {}
        @raw_lines = []

        content.to_s.each_line do |line|
          @raw_lines << line
          clean = line.strip

          # Skip comments and blank lines
          next if clean.empty? || clean.start_with?('#', ';')

          eq_idx = clean.index('=')
          next if eq_idx.nil?

          var = clean[0...eq_idx].strip.downcase
          val = clean[(eq_idx + 1)..].strip

          @directives[var] = val
        end

        self
      end

      def get(key, default = nil)
        k = key.to_s.downcase
        return default unless @directives.key?(k)

        val = @directives[k]

        if BOOLEAN_DIRECTIVES.include?(k)
          val.to_i == 1 || val.casecmp('true').zero?
        elsif INTEGER_DIRECTIVES.include?(k)
          val.to_i
        elsif CONTACT_LIST_DIRECTIVES.include?(k)
          val.split(',').map(&:strip).reject(&:empty?)
        else
          val
        end
      end

      def [](key)
        get(key)
      end

      def set(key, val)
        @directives[key.to_s.downcase] = val.is_a?(Array) ? val.join(',') : val.to_s
      end

      # Helper predicates and accessors
      def authentication_enabled?
        get('use_authentication', true)
      end

      def refresh_rate
        get('refresh_rate', DEFAULT_REFRESH_RATE)
      end

      def result_limit
        get('result_limit', DEFAULT_RESULT_LIMIT)
      end

      def main_config_file
        get('main_config_file', 'nagios.cfg')
      end

      def contacts_authorized_for(capability)
        key = "authorized_for_#{capability}".downcase
        get(key, [])
      end

      def user_authorized_for?(user, capability)
        u = user.to_s.strip
        contacts = contacts_authorized_for(capability)
        return true if contacts.include?('*')

        contacts.include?(u)
      end

      # Validates parsed CGI directives
      def validate
        errors = []
        warnings = []

        if authentication_enabled?
          admin_contacts = contacts_authorized_for('system_information')
          warnings << 'No contacts authorized for system_information' if admin_contacts.empty?
        end

        rate = refresh_rate
        warnings << 'refresh_rate is below 5 seconds' if rate.positive? && rate < 5

        {
          valid: errors.empty?,
          errors: errors,
          warnings: warnings
        }
      end

      # Serializes configuration back to cgi.cfg format
      def to_cfg
        lines = []
        lines << '# Nagios CGI Configuration File (cgi.cfg)'
        lines << "# Generated at #{Time.now}"
        lines << ''

        @directives.sort.each do |k, v|
          lines << "#{k}=#{v}"
        end

        lines.join("\n") + "\n"
      end

      def to_h
        result = {}
        @directives.each_key do |k|
          result[k] = get(k)
        end
        result
      end
    end
  end
end
