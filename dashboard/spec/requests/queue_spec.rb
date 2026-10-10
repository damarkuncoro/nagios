# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Queue", type: :request do
  describe "GET /queue" do
    it "returns http success and renders scheduling queue and spread metrics" do
      get queue_path, headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Scheduling Queue & Distribution")
      expect(response.body).to include("Total in Queue")
      expect(response.body).to include("Due in ≤ 1 Min")
    end

    it "filters queue by host checks" do
      get queue_path(filter: 'host'), headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Host Checks")
    end

    it "filters queue by service checks" do
      get queue_path(filter: 'service'), headers: { "Host" => "localhost" }
      expect(response).to have_http_status(:success)
      expect(response.body).to include("Service Checks")
    end
  end
end
