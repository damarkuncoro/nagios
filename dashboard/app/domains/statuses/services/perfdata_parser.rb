# frozen_string_literal: true

module Statuses
  module Services
    # Adopts parse_check_output from base/checks.c and performance data handling from base/perfdata.c
    # Implements official Nagios Plugin Performance Data specification parser:
    # 'label'=value[UOM];[warn];[crit];[min];[max]
    class PerfdataParser
      ParsedOutput = Struct.new(
        :short_output,
        :long_output,
        :perf_data_string,
        :metrics,
        keyword_init: true
      ) do
        def has_metrics?
          metrics.present?
        end

        def metric(label)
          metrics.find { |m| m.label == label.to_s }
        end
      end

      Metric = Struct.new(
        :label,
        :value,
        :uom,
        :warn,
        :crit,
        :min,
        :max,
        :status,
        keyword_init: true
      ) do
        def percentage
          return nil unless min && max && max > min && value

          (((value - min) / (max - min).to_f) * 100.0).round(1)
        end

        def critical?
          status == :critical
        end

        def warning?
          status == :warning
        end

        def ok?
          status == :ok
        end
      end

      class << self
        # Parses complete plugin output string into short output, long output, and structured metrics
        # (base/checks.c parse_check_output lines 3415-3480)
        def parse(raw_output)
          return ParsedOutput.new(short_output: '', long_output: '', perf_data_string: '', metrics: []) if raw_output.nil? || raw_output.to_s.strip.empty?

          text = raw_output.to_s
          lines = text.split("\n")
          first_line = lines.first || ''

          short_output = ''
          perf_string = ''
          long_output_lines = []

          # Check for pipe in the first line
          if first_line.include?('|')
            short_part, perf_part = first_line.split('|', 2)
            short_output = short_part.strip
            perf_string = perf_part.strip
          else
            short_output = first_line.strip
          end

          # Subsequent lines can be long output or continuation of perf data
          in_perf = false
          lines[1..].to_a.each do |line|
            if in_perf
              perf_string = "#{perf_string} #{line.strip}".strip
            elsif line.include?('|')
              long_part, perf_part = line.split('|', 2)
              long_output_lines << long_part.strip if long_part.strip.present?
              perf_string = "#{perf_string} #{perf_part.strip}".strip
              in_perf = true
            else
              long_output_lines << line.strip
            end
          end

          metrics = parse_metrics(perf_string)

          ParsedOutput.new(
            short_output: short_output,
            long_output: long_output_lines.join("\n"),
            perf_data_string: perf_string,
            metrics: metrics
          )
        end

        # Parses raw performance data string into Metric objects
        # Format: 'label'=value[UOM];[warn];[crit];[min];[max] ...
        def parse_metrics(perf_string)
          return [] if perf_string.nil? || perf_string.to_s.strip.empty?

          metrics = []
          # Regex matches quoted or unquoted labels and their semicolon-separated parameters
          # e.g. 'rta'=0.050ms;100.000;500.000;0; or load1=0.15;1.00;2.00;0;
          pattern = /(?:'([^']+)'|([^\s=]+))=([^\s;]+)(?:;([^\s;]*))?(?:;([^\s;]*))?(?:;([^\s;]*))?(?:;([^\s;]*))?/

          perf_string.scan(pattern) do |quoted_label, unquoted_label, raw_val, warn, crit, min, max|
            label = quoted_label || unquoted_label
            next if label.nil? || label.to_s.strip.empty?

            num_val, uom = split_value_and_uom(raw_val)
            w_val = coerce_num(warn)
            c_val = coerce_num(crit)
            min_val = coerce_num(min)
            max_val = coerce_num(max)

            status = evaluate_metric_status(num_val, w_val, c_val)

            metrics << Metric.new(
              label: label,
              value: num_val,
              uom: uom,
              warn: w_val,
              crit: c_val,
              min: min_val,
              max: max_val,
              status: status
            )
          end

          metrics
        end

        # Formats metrics into default template string (base/xpddefault.c)
        def format_template(host_name:, service_desc: nil, perf_data_string:, timestamp: nil)
          ts = timestamp || (Time.respond_to?(:current) ? Time.current : Time.now).to_i

          if service_desc && !service_desc.to_s.strip.empty?
            # DEFAULT_SERVICE_PERFDATA_FILE_TEMPLATE
            "DATATYPE::SERVICEPERFDATA\tTIMET::#{ts}\tHOSTNAME::#{host_name}\tSERVICEDESC::#{service_desc}\tSERVICEPERFDATA::#{perf_data_string}\n"
          else
            # DEFAULT_HOST_PERFDATA_FILE_TEMPLATE
            "DATATYPE::HOSTPERFDATA\tTIMET::#{ts}\tHOSTNAME::#{host_name}\tHOSTPERFDATA::#{perf_data_string}\n"
          end
        end

        private

        def split_value_and_uom(raw)
          return [0.0, ''] if raw.nil? || raw.to_s.strip.empty?

          if raw =~ /^(-?[\d\.]+)\s*([a-zA-Z%]+)?$/
            num = $1.include?('.') ? $1.to_f : $1.to_i
            uom = $2.to_s
            [num, uom]
          elsif %w[U UNKNOWN].include?(raw.to_s.upcase)
            [nil, '']
          else
            [raw.to_f, '']
          end
        end

        def coerce_num(val)
          return nil if val.nil? || val.to_s.strip.empty?

          cleaned = val.to_s.strip
          if cleaned =~ /^-?\d+\.\d+$/
            cleaned.to_f
          elsif cleaned =~ /^-?\d+$/
            cleaned.to_i
          else
            cleaned.to_f rescue nil
          end
        end

        def evaluate_metric_status(val, warn, crit)
          return :ok if val.nil?

          if crit && val >= crit
            :critical
          elsif warn && val >= warn
            :warning
          else
            :ok
          end
        end
      end
    end
  end
end
