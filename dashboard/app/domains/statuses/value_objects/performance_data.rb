module Statuses
  module ValueObjects
    class PerformanceData
      attr_reader :raw, :type, :value, :unit, :used_percentage

      def initialize(raw_perf, description: '', plugin_output: '')
        @raw = raw_perf.to_s
        parse(description.to_s.downcase, plugin_output.to_s)
      end

      def disk?
        type == :disk
      end

      def load?
        type == :load
      end

      def ping?
        type == :ping
      end

      private

      def parse(desc, output)
        if desc.include?("partition") || desc.include?("disk") || desc.include?("space")
          @type = :disk
          if output =~ /(\d+(?:\.\d+)?)\%/
            free_pct = $1.to_f
            @used_percentage = (100.0 - free_pct).round(1)
          end
        elsif desc.include?("load")
          @type = :load
          if output =~ /load average:\s*([\d\.]+),\s*([\d\.]+),\s*([\d\.]+)/i
            @value = { l1: $1, l5: $2, l15: $3 }
          end
        elsif desc.include?("ping")
          @type = :ping
          if output =~ /RTA\s*=\s*([\d\.]+)\s*ms/i
            @value = $1.to_f
            @unit = 'ms'
          end
        else
          @type = :generic
        end
      end
    end
  end
end
