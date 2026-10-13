# frozen_string_literal: true

module Discovery
  module Services
    # Generates Nagios host/service object definitions and hot-reloads the monitoring engine.
    class DeviceImporter
      def self.import(device = {}, cfg_path: nil, **kwargs)
        payload = kwargs.any? ? kwargs : device
        new(cfg_path: cfg_path).import(payload)
      end

      def initialize(cfg_path: nil)
        @cfg_path = cfg_path || Rails.root.join('config/nagios_sample.cfg').to_s
      end

      def import(device)
        dev = device.to_h.with_indifferent_access
        host_name = clean_host_name(dev[:hostname] || dev[:ip])
        alias_name = "#{dev[:vendor]} - #{dev[:device_type]} (#{dev[:ip]})"
        address = dev[:ip]
        existing_cfg = File.exist?(@cfg_path) ? File.read(@cfg_path) : ''

        if existing_cfg.match?(/address\s+#{Regexp.escape(address)}\b/)
          return { success: false, error: "Host dengan IP #{address} sudah terdaftar dalam monitoring." }
        end

        parent_host = determine_parent(existing_cfg, host_name)
        host_def = build_host_and_services(host_name, alias_name, address, parent_host, dev)

        File.open(@cfg_path, 'a') do |f|
          f.puts host_def
        end

        # Hot-reload monitoring daemon
        Engines::NagiosEngine.new.reload_config rescue nil

        { success: true, host_name: host_name }
      rescue StandardError => e
        { success: false, error: e.message }
      end

      private

      def determine_parent(cfg, current_name)
        return nil if current_name == 'localhost' || current_name == 'gateway'

        if cfg.include?('mikrotik_core_router') && current_name != 'mikrotik_core_router'
          'mikrotik_core_router'
        elsif cfg.include?('gateway')
          'gateway'
        end
      end

      def build_host_and_services(name, alias_name, address, parent, dev)
        ports = dev[:open_ports].to_s
        parent_line = parent ? "\n    parents                 #{parent}" : ''

        buf = <<~CFG

          # Automatically discovered by NetworkScanner on #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}
          define host {
              host_name               #{name}
              alias                   #{alias_name}
              address                 #{address}#{parent_line}
              max_check_attempts      3
              check_interval          15
              retry_interval          3
              check_command           check_ping!100.0,20%!500.0,60%
              notifications_enabled   1
          }

          define service {
              host_name               #{name}
              service_description     Ping Latency
              check_command           check_ping!100.0,20%!500.0,60%
              check_interval          15
              retry_interval          3
              max_check_attempts      3
              notifications_enabled   1
          }
        CFG

        if ports.include?('8291')
          buf += service_chunk(name, 'Winbox Management Port', 'check_tcp!8291')
        end
        if ports.include?('80')
          buf += service_chunk(name, 'Web Management GUI', 'check_http!80!/')
        end
        if ports.include?('53')
          buf += service_chunk(name, 'DNS Gateway Resolver', 'check_tcp!53')
        end
        if ports.include?('22')
          buf += service_chunk(name, 'SSH Management Port', 'check_tcp!22')
        end
        if dev[:snmp_descr].present? || ports.include?('161')
          buf += service_chunk(name, 'SNMP System Info', 'check_snmp!1.3.6.1.2.1.1.1.0!public')
        end
        buf
      end

      def service_chunk(host, desc, cmd)
        <<~CFG
          define service {
              host_name               #{host}
              service_description     #{desc}
              check_command           #{cmd}
              check_interval          20
              retry_interval          3
              max_check_attempts      3
              notifications_enabled   1
          }
        CFG
      end

      def clean_host_name(raw)
        name = raw.to_s.gsub(/[^a-zA-Z0-9_\-.]/, '_')
        name = "dev_#{name}" if name =~ /\A[0-9]/
        name.presence || "host_#{rand(1000..9999)}"
      end
    end
  end
end
