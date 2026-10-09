require 'csv'

class AvailabilityController < ApplicationController
  def index
    @report = Statuses::UseCases::FetchAvailabilityReport.call

    respond_to do |format|
      format.html
      format.csv do
        csv_data = CSV.generate(headers: true) do |csv|
          csv << ["Type", "Host Name", "Service Description", "Status", "Availability %", "SLA Compliance"]

          @report[:host_reports].each do |hr|
            csv << ["Host", hr[:name], "-", hr[:status], "#{hr[:availability_pct]}%", hr[:sla_met] ? "PASSED" : "BREACHED"]
          end

          @report[:service_reports].each do |sr|
            csv << ["Service", sr[:host_name], sr[:description], sr[:status], "#{sr[:availability_pct]}%", sr[:sla_met] ? "PASSED" : "WARNING"]
          end
        end

        send_data csv_data, filename: "nagios_sla_report_#{Date.today}.csv", type: "text/csv"
      end
    end
  end
end
