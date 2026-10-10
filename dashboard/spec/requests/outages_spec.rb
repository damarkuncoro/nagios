require 'rails_helper'

RSpec.describe "Outages", type: :request do
  describe "GET /outages" do
    it "renders the network outages page successfully" do
      get outages_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Network Outages")
      expect(response.body).to include("Root Cause Analysis")
    end
  end
end
