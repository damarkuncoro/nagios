require 'csv'

module Statuses
  module UseCases
    class ExportNotificationsCsv
      def self.call(notifications)
        new(notifications).call
      end

      def initialize(notifications)
        @notifications = notifications || []
      end

      def call
        CSV.generate(headers: true) do |csv|
          csv << [
            'Timestamp',
            'Host Name',
            'Service Description',
            'Contact Name',
            'Notification Type',
            'State',
            'Output'
          ]

          @notifications.each do |n|
            csv << [
              n[:timestamp]&.strftime('%Y-%m-%d %H:%M:%S') || 'N/A',
              n[:host_name],
              n[:service_desc] || 'HOST ALERT',
              n[:contact_name],
              n[:notification_type],
              n[:state],
              n[:output]
            ]
          end
        end
      end
    end
  end
end
