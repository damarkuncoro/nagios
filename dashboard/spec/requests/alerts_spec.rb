require 'rails_helper'

RSpec.describe "Alerts", type: :request do
  describe "GET /alerts" do
    it "returns http success" do
      get alerts_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Alert History")
    end
  end
end
