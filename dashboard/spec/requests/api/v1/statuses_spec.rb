require 'rails_helper'

RSpec.describe "Api::V1::Statuses", type: :request do
  let(:headers) { { "Host" => "localhost" } }

  describe "GET /api/v1/status" do
    it "returns JSON dashboard status" do
      get "/api/v1/status", headers: headers
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/json")

      json = JSON.parse(response.body)
      expect(json).to have_key("hosts")
      expect(json).to have_key("services")
      expect(json).to have_key("host_stats")
      expect(json).to have_key("service_stats")
    end
  end

  describe "GET /api/v1/tactical" do
    it "returns JSON tactical overview" do
      get "/api/v1/tactical", headers: headers
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/json")

      json = JSON.parse(response.body)
      expect(json).to have_key("host_health_pct")
      expect(json).to have_key("service_health_pct")
    end
  end

  describe "GET /api/v1/problems" do
    it "returns JSON unhandled problems" do
      get "/api/v1/problems", headers: headers
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include("application/json")

      json = JSON.parse(response.body)
      expect(json).to have_key("hosts")
      expect(json).to have_key("services")
      expect(json).to have_key("total_unhandled")
    end
  end
end
