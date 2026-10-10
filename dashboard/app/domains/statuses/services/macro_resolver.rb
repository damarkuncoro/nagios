# frozen_string_literal: true

module Statuses
  module Services
    # Adopts read_resource_file() from base/config.c
    # Parses $USER1$..$USER256$ macros and resolves runtime command lines
    class MacroResolver
      DEFAULT_RESOURCE_PATH = ENV.fetch('NAGIOS_RESOURCE_CFG', '/nagios_var/resource.cfg')
      DEFAULT_PLUGINS_PATH = ENV.fetch('NAGIOS_PLUGINS_PATH', '/opt/nagios/libexec')

      class << self
        def macros
          @macros ||= load_resource_file
        end

        def reload!
          @macros = load_resource_file
        end

        def resolve(template, host: nil, service: nil, bang_args: [])
          return '' if template.blank?

          expanded = template.dup

          # 1. Resolve $USERx$ macros (base/config.c read_resource_file)
          macros.each do |macro, value|
            expanded.gsub!(macro, value)
          end

          # 2. Resolve Host & Service macros
          if host.present?
            h_name = host.is_a?(Hash) ? host['name'] : (host.respond_to?(:name) ? host.name : host.to_s)
            h_addr = host.is_a?(Hash) ? host['address'] : (host.respond_to?(:address) ? host.address : '127.0.0.1')
            expanded.gsub!('$HOSTNAME$', h_name.to_s)
            expanded.gsub!('$HOSTADDRESS$', (h_addr.presence || '127.0.0.1').to_s)
          end

          if service.present?
            s_desc = service.is_a?(Hash) ? service['description'] : (service.respond_to?(:description) ? service.description : service.to_s)
            expanded.gsub!('$SERVICEDESC$', s_desc.to_s)
          end

          # 3. Resolve $ARG1$, $ARG2$, etc.
          bang_args.each_with_index do |arg, idx|
            expanded.gsub!("$ARG#{idx + 1}$", arg.to_s)
          end

          expanded
        end

        private

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
              macro_map[key] = val if val.present?
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
