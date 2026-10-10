# frozen_string_literal: true

module Statuses
  module Services
    # Adopts comprehensive macro expansion from common/macros.c
    # Expands $USER1$..$USER256$, Host, Service, Date/Time, and Notification macros.
    class MacroResolver
      DEFAULT_RESOURCE_PATH = ENV.fetch('NAGIOS_RESOURCE_CFG', '/nagios_var/resource.cfg')
      DEFAULT_PLUGINS_PATH = ENV.fetch('NAGIOS_PLUGINS_PATH', '/opt/nagios/libexec')

      HOST_STATE_MAP = {
        'UP' => 0,
        'DOWN' => 1,
        'UNREACHABLE' => 2
      }.freeze

      SVC_STATE_MAP = {
        'OK' => 0,
        'WARNING' => 1,
        'CRITICAL' => 2,
        'UNKNOWN' => 3
      }.freeze

      class << self
        def macros
          @macros ||= load_resource_file
        end

        def reload!
          @macros = load_resource_file
        end

        # Resolves template string replacing Nagios macros (common/macros.c: process_macros)
        def resolve(template, host: nil, service: nil, bang_args: [], notification: {}, contact: {})
          return '' if template.nil? || template.to_s.strip.empty?

          expanded = template.dup

          # 1. Resolve $USERx$ macros (base/config.c & resource.cfg)
          macros.each do |macro, value|
            expanded.gsub!(macro, value.to_s)
          end

          # 2. Resolve Date & Time macros (common/macros.c lines 1120-1160)
          now = Time.respond_to?(:current) ? Time.current : Time.now
          expanded.gsub!('$LONGDATETIME$', now.strftime('%a %b %d %H:%M:%S %Z %Y'))
          expanded.gsub!('$SHORTDATETIME$', now.strftime('%Y-%m-%d %H:%M:%S'))
          expanded.gsub!('$DATE$', now.strftime('%Y-%m-%d'))
          expanded.gsub!('$TIME$', now.strftime('%H:%M:%S'))
          expanded.gsub!('$TIMET$', now.to_i.to_s)

          # 3. Resolve Host macros (common/macros.c lines 1300-1550)
          if host
            resolve_host_macros(expanded, host)
          end

          # 4. Resolve Service macros (common/macros.c lines 1600-1850)
          if service
            resolve_service_macros(expanded, service)
          end

          # 5. Resolve Notification & Contact macros (common/macros.c lines 1900-2050)
          resolve_notification_macros(expanded, notification, contact)

          # 6. Resolve Command arguments $ARG1$, $ARG2$, etc.
          Array(bang_args).each_with_index do |arg, idx|
            expanded.gsub!("$ARG#{idx + 1}$", arg.to_s)
          end

          expanded
        end

        private

        def resolve_host_macros(str, host)
          h_name = get_attr(host, :name) || host.to_s
          h_alias = get_attr(host, :alias) || h_name
          h_addr = get_attr(host, :address) || '127.0.0.1'
          h_state = (get_attr(host, :status) || get_attr(host, :current_state) || 'UP').to_s.upcase
          h_last_state = (get_attr(host, :last_state) || h_state).to_s.upcase
          h_state_type = (get_attr(host, :state_type) || 'HARD').to_s.upcase
          h_attempt = (get_attr(host, :current_attempt) || 1).to_i
          h_max_attempts = (get_attr(host, :max_attempts) || 1).to_i
          h_output = get_attr(host, :plugin_output) || ''
          h_perfdata = get_attr(host, :perf_data) || ''

          str.gsub!('$HOSTNAME$', h_name.to_s)
          str.gsub!('$HOSTALIAS$', h_alias.to_s)
          str.gsub!('$HOSTADDRESS$', h_addr.to_s)
          str.gsub!('$HOSTSTATE$', h_state)
          str.gsub!('$HOSTSTATEID$', (HOST_STATE_MAP[h_state] || 0).to_s)
          str.gsub!('$LASTHOSTSTATE$', h_last_state)
          str.gsub!('$LASTHOSTSTATEID$', (HOST_STATE_MAP[h_last_state] || 0).to_s)
          str.gsub!('$HOSTSTATETYPE$', h_state_type)
          str.gsub!('$HOSTATTEMPT$', h_attempt.to_s)
          str.gsub!('$MAXHOSTATTEMPTS$', h_max_attempts.to_s)
          str.gsub!('$HOSTOUTPUT$', h_output.to_s)
          str.gsub!('$HOSTPERFDATA$', h_perfdata.to_s)
        end

        def resolve_service_macros(str, service)
          s_desc = get_attr(service, :description) || service.to_s
          s_state = (get_attr(service, :status) || get_attr(service, :current_state) || 'OK').to_s.upcase
          s_last_state = (get_attr(service, :last_state) || s_state).to_s.upcase
          s_state_type = (get_attr(service, :state_type) || 'HARD').to_s.upcase
          s_attempt = (get_attr(service, :current_attempt) || 1).to_i
          s_max_attempts = (get_attr(service, :max_attempts) || 1).to_i
          s_output = get_attr(service, :plugin_output) || ''
          s_perfdata = get_attr(service, :perf_data) || ''

          str.gsub!('$SERVICEDESC$', s_desc.to_s)
          str.gsub!('$SERVICESTATE$', s_state)
          str.gsub!('$SERVICESTATEID$', (SVC_STATE_MAP[s_state] || 0).to_s)
          str.gsub!('$LASTSERVICESTATE$', s_last_state)
          str.gsub!('$LASTSERVICESTATEID$', (SVC_STATE_MAP[s_last_state] || 0).to_s)
          str.gsub!('$SERVICESTATETYPE$', s_state_type)
          str.gsub!('$SERVICEATTEMPT$', s_attempt.to_s)
          str.gsub!('$MAXSERVICEATTEMPTS$', s_max_attempts.to_s)
          str.gsub!('$SERVICEOUTPUT$', s_output.to_s)
          str.gsub!('$SERVICEPERFDATA$', s_perfdata.to_s)
        end

        def resolve_notification_macros(str, notif, contact)
          n_type = (get_attr(notif, :type) || 'PROBLEM').to_s.upcase
          n_number = (get_attr(notif, :number) || 1).to_i
          c_name = get_attr(contact, :name) || 'nagiosadmin'
          c_alias = get_attr(contact, :alias) || c_name
          c_email = get_attr(contact, :email) || 'root@localhost'

          str.gsub!('$NOTIFICATIONTYPE$', n_type)
          str.gsub!('$NOTIFICATIONNUMBER$', n_number.to_s)
          str.gsub!('$CONTACTNAME$', c_name.to_s)
          str.gsub!('$CONTACTALIAS$', c_alias.to_s)
          str.gsub!('$CONTACTEMAIL$', c_email.to_s)
        end

        def get_attr(target, attr_name)
          return nil if target.nil?

          if target.is_a?(Hash)
            target[attr_name.to_s] || target[attr_name.to_sym]
          elsif target.respond_to?(attr_name)
            target.send(attr_name)
          end
        end

        def load_resource_file
          macro_map = { '$USER1$' => DEFAULT_PLUGINS_PATH }

          file_path = [DEFAULT_RESOURCE_PATH, '/opt/nagios/etc/resource.cfg'].find { |p| File.exist?(p) }
          return macro_map unless file_path

          File.foreach(file_path) do |line|
            cleaned = line.strip
            next if cleaned.empty? || cleaned.start_with?('#')

            if cleaned =~ /^(\$USER\d+\$)=(.*)$/
              key = ::Regexp.last_match(1)
              val = ::Regexp.last_match(2).to_s.strip
              macro_map[key] = val unless val.empty?
            end
          end

          macro_map
        rescue StandardError
          macro_map
        end
      end
    end
  end
end
