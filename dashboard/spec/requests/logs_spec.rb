require 'rails_helper'

RSpec.describe "Logs", type: :request do
  describe "GET /logs" do
    it "renders the live event log page successfully" do
      get logs_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Live Event Log")
      expect(response.body).to include("nagios.log")
    end

    it "filters logs by category type" do
      get logs_path(type: "ALERT"), headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Filter: ALERT")
    end
  end
end
