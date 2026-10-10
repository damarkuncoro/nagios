require 'csv'

module Statuses
  module UseCases
    class ExportNotificationsCsv
      def self.call(notifications)
        Services::NotificationHistoryManager.export_csv(notifications)
      end
    end
  end
end
