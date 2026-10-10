# frozen_string_literal: true

require 'fileutils'
require 'time'

module Statuses
  module Services
    # Adopts default performance data file processing & spooling from xdata/xpddefault.c
    # Formats host & service performance data records via customizable templates,
    # generates Graphite/Carbon and Prometheus/OpenMetrics telemetry streams,
    # and handles atomic spool file rotation for downstream metric collectors.
    class PerformanceDataProcessor
      DEFAULT_HOST_TEMPLATE = "DATATYPE::HOSTPERFDATA\tTIMET::$TIMET$\tHOSTNAME::$HOSTNAME$\tHOSTSTATE::$HOSTSTATE$\tHOSTSTATETYPE::$HOSTSTATETYPE$\tHOSTEXECUTIONTIME::$HOSTEXECUTIONTIME$\tHOSTPERFDATA::$HOSTPERFDATA$"
      DEFAULT_SERVICE_TEMPLATE = "DATATYPE::SERVICEPERFDATA\tTIMET::$TIMET$\tHOSTNAME::$HOSTNAME$\tSERVICEDESC::$SERVICEDESC$\tSERVICESTATE::$SERVICESTATE$\tSERVICESTATETYPE::$SERVICESTATETYPE$\tSERVICEEXECUTIONTIME::$SERVICEEXECUTIONTIME$\tSERVICELATENCY::$SERVICELATENCY$\tSERVICEPERFDATA::$SERVICEPERFDATA$"

      class << self
        def format_host(host, template: DEFAULT_HOST_TEMPLATE, timet: Time.now.to_i)
          new.format_host(host, template: template, timet: timet)
        end

        def format_service(service, host: nil, template: DEFAULT_SERVICE_TEMPLATE, timet: Time.now.to_i)
          new.format_service(service, host: host, template: template, timet: timet)
        end

        def to_graphite(target, prefix: 'nagios', timet: Time.now.to_i)
          new.to_graphite(target, prefix: prefix, timet: timet)
        end

        def to_prometheus(hosts: [], services: [])
          new.to_prometheus(hosts: hosts, services: services)
        end

        def rotate_spool(file_path)
          new.rotate_spool(file_path)
        end
      end

      # Formats host perfdata record (xdata/xpddefault.c: xpddefault_update_host_performance_data_file)
      def format_host(host, template: DEFAULT_HOST_TEMPLATE, timet: Time.now.to_i)
        macros = build_host_macro_map(host, timet)
        expand_template(template, macros)
      end

      # Formats service perfdata record (xdata/xpddefault.c: xpddefault_update_service_performance_data_file)
      def format_service(service, host: nil, template: DEFAULT_SERVICE_TEMPLATE, timet: Time.now.to_i)
        macros = build_service_macro_map(service, host, timet)
        expand_template(template, macros)
      end

      # Converts parsed metrics to Graphite plaintext lines: <path> <val> <timet>
      def to_graphite(target, prefix: 'nagios', timet: Time.now.to_i)
        lines = []
        h_name = sanitize_metric_key(get_attr(target, :host_name) || get_attr(target, :name))
        s_desc = sanitize_metric_key(get_attr(target, :description) || get_attr(target, :service_description))

        raw_perf = get_attr(target, :performance_data) || get_attr(target, :perf_data) || ''
        metrics = extract_metrics(raw_perf)

        path_prefix = s_desc.empty? ? "#{prefix}.hosts.#{h_name}" : "#{prefix}.services.#{h_name}.#{s_desc}"

        metrics.each do |m|
          metric_label = sanitize_metric_key(m.label)
          lines << "#{path_prefix}.#{metric_label} #{m.value} #{timet}"
        end

        lines
      end

      # Converts hosts and services metrics to Prometheus / OpenMetrics Exposition format
      def to_prometheus(hosts: [], services: [])
        lines = []
        lines << '# HELP nagios_service_metric Metric values reported by Nagios service check plugins'
        lines << '# TYPE nagios_service_metric gauge'

        Array(services).each do |s|
          h_name = get_attr(s, :host_name).to_s
          s_desc = (get_attr(s, :description) || get_attr(s, :service_description)).to_s
          raw_perf = get_attr(s, :performance_data) || get_attr(s, :perf_data) || ''

          metrics = extract_metrics(raw_perf)
          metrics.each do |m|
            uom = m.uom.to_s
            lines << %(nagios_service_metric{host="#{escape_prom(h_name)}",service="#{escape_prom(s_desc)}",metric="#{escape_prom(m.label)}",unit="#{escape_prom(uom)}"} #{m.value})
          end
        end

        lines << '# HELP nagios_host_up Host status indicator (1=UP, 0=DOWN/UNREACHABLE)'
        lines << '# TYPE nagios_host_up gauge'

        Array(hosts).each do |h|
          h_name = get_attr(h, :name).to_s
          st = (get_attr(h, :status) || 'UP').to_s.upcase
          val = st == 'UP' ? 1 : 0
          lines << %(nagios_host_up{host="#{escape_prom(h_name)}"} #{val})
        end

        lines.join("\n") + "\n"
      end

      # Atomically rotates spool file and reads records (xdata/xpddefault.c: process_service_perfdata_file)
      def rotate_spool(file_path)
        return [] unless File.exist?(file_path) && File.size(file_path).positive?

        epoch = Time.now.to_i
        processing_path = "#{file_path}.processing.#{epoch}.#{Process.pid}"

        begin
          File.rename(file_path, processing_path)
        rescue Errno::ENOENT
          return []
        end

        lines = []
        File.open(processing_path, 'r') do |f|
          f.each_line do |line|
            cleaned = line.strip
            lines << cleaned unless cleaned.empty?
          end
        end

        FileUtils.rm_f(processing_path)
        lines
      end

      private

      def build_host_macro_map(host, timet)
        name = get_attr(host, :name).to_s
        st = (get_attr(host, :status) || 'UP').to_s.upcase
        st_type = (get_attr(host, :state_type) || 'HARD').to_s.upcase
        exec_t = (get_attr(host, :execution_time) || 0.0).to_f
        perfdata = (get_attr(host, :performance_data) || get_attr(host, :perf_data)).to_s

        {
          '$TIMET$' => timet.to_s,
          '$HOSTNAME$' => name,
          '$HOSTSTATE$' => st,
          '$HOSTSTATETYPE$' => st_type,
          '$HOSTEXECUTIONTIME$' => format('%.3f', exec_t),
          '$HOSTPERFDATA$' => perfdata
        }
      end

      def build_service_macro_map(service, host, timet)
        h_name = host ? get_attr(host, :name).to_s : get_attr(service, :host_name).to_s
        s_desc = (get_attr(service, :description) || get_attr(service, :service_description)).to_s
        st = (get_attr(service, :status) || 'OK').to_s.upcase
        st_type = (get_attr(service, :state_type) || 'HARD').to_s.upcase
        exec_t = (get_attr(service, :execution_time) || 0.0).to_f
        lat = (get_attr(service, :latency) || 0.0).to_f
        perfdata = (get_attr(service, :performance_data) || get_attr(service, :perf_data)).to_s

        {
          '$TIMET$' => timet.to_s,
          '$HOSTNAME$' => h_name,
          '$SERVICEDESC$' => s_desc,
          '$SERVICESTATE$' => st,
          '$SERVICESTATETYPE$' => st_type,
          '$SERVICEEXECUTIONTIME$' => format('%.3f', exec_t),
          '$SERVICELATENCY$' => format('%.3f', lat),
          '$SERVICEPERFDATA$' => perfdata
        }
      end

      def expand_template(template, macros)
        result = template.dup
        macros.each do |k, v|
          result.gsub!(k, v)
        end
        result
      end

      def sanitize_metric_key(str)
        str.to_s.strip.downcase.gsub(/[^a-z0-9_-]/, '_').squeeze('_').sub(/^_+/, '').sub(/_+$/, '')
      end

      def extract_metrics(raw)
        s = raw.to_s.strip
        return [] if s.empty?

        if s.include?('|')
          PerfdataParser.parse(s).metrics
        else
          PerfdataParser.parse_metrics(s)
        end
      end

      def escape_prom(str)
        str.to_s.gsub('\\', '\\\\').gsub('"', '\"').gsub("\n", '\\n')
      end

      def get_attr(target, key)
        return nil if target.nil?

        if target.is_a?(Hash)
          target[key.to_s] || target[key.to_sym]
        elsif target.respond_to?(key)
          target.send(key)
        end
      end
    end
  end
end
