require 'csv'

module Statuses
  module UseCases
    class ExportHostsCsv
      def self.call(hosts)
        new(hosts).call
      end

      def initialize(hosts)
        @hosts = hosts || []
      end

      def call
        CSV.generate(headers: true) do |csv|
          csv << [
            'Host Name',
            'Status',
            'Checks Enabled',
            'Notifications Enabled',
            'Acknowledged',
            'Last Check',
            'Next Check',
            'Plugin Output'
          ]

          @hosts.each do |h|
            host_data = h.respond_to?(:to_h) ? h.to_h : h
            csv << [
              host_data[:name],
              host_data[:status],
              host_data[:checks_enabled] ? 'YES' : 'NO',
              host_data[:notifications_enabled] ? 'YES' : 'NO',
              host_data[:acknowledged] ? 'YES' : 'NO',
              host_data[:last_check]&.strftime('%Y-%m-%d %H:%M:%S') || 'N/A',
              host_data[:next_check]&.strftime('%Y-%m-%d %H:%M:%S') || 'N/A',
              host_data[:plugin_output]
            ]
          end
        end
      end
    end
  end
end
